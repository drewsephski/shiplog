import { SignJWT, importPKCS8 } from 'jose';
import { createPrivateKey } from 'node:crypto';
import { z } from 'zod';
import { db } from './db';
import { encrypt, decrypt, PublicError, required, publicURL } from './security';
import { evidenceID, type ActivityEvidence, type ConnectedRepository, type RepoContext } from './domain';

const githubUser = z.object({id:z.number().int(), login:z.string()});
const repoSchema = z.object({
  id:z.number().int(), name:z.string(), full_name:z.string(), html_url:z.url(),
  description:z.string().nullable(), private:z.boolean(), default_branch:z.string(),
});
const installationSchema = z.object({id:z.number().int(), app_id:z.number().int(), suspended_at:z.string().nullable(),
  permissions:z.record(z.string(),z.string())});
export class GitHubError extends PublicError {
  constructor(status: number, retryAfter = 300) {
    super(status === 429 ? 429 : 502, status===429 ? 'github_rate_limited' : status === 401 || status === 403 || status === 404 ? 'github_access' : 'github_unavailable',
      status === 401 || status === 403 || status === 404
        ? 'GitHub access changed. Reconnect and check repository permissions.'
        : 'GitHub is unavailable or rate limited. Shiplog will retry.',retryAfter);
  }
}
async function githubFailure(response: Response): Promise<GitHubError> {
  let message='';
  try { const body=z.object({message:z.string()}).safeParse(await response.json());if(body.success) message=body.data.message; } catch {}
  const limited=response.status===429 || response.status===403 &&
    (response.headers.get('x-ratelimit-remaining')==='0' || response.headers.has('retry-after') || /rate limit/i.test(message));
  const reset=Number(response.headers.get('x-ratelimit-reset'))*1000;
  const retry=Number(response.headers.get('retry-after'));
  const delay=Math.min(86_400,Math.max(60,retry || 0,Number.isFinite(reset) ? Math.ceil((reset-Date.now())/1000) : 0));
  return new GitHubError(limited ? 429 : response.status,limited ? delay : 300);
}
export async function github<T>(path: string, token: string, schema: z.ZodType<T>, init: RequestInit = {}): Promise<T> {
  if (!path.startsWith('/') || path.startsWith('//')) throw new Error('Invalid GitHub path');
  const response = await fetch(`https://api.github.com${path}`, {
    ...init, cache:'no-store', redirect:'error', signal:AbortSignal.timeout(15_000),
    headers:{accept:'application/vnd.github+json','X-GitHub-Api-Version':'2026-03-10',
      authorization:`Bearer ${token}`,'User-Agent':'Shiplog-Agent','Content-Type':'application/json'},
  });
  if (!response.ok) throw await githubFailure(response);
  return schema.parse(await response.json());
}
export async function pages<T>(path: string, token: string, schema: z.ZodType<T>, key?: string): Promise<T[]> {
  const output: T[] = [];
  for (let page=1; page<=20; page++) {
    const paginated = `${path}${path.includes('?') ? '&' : '?'}per_page=100&page=${page}`;
    const items = key ? (await github(paginated,token,z.object({[key]:z.array(schema)})))[key]
      : await github(paginated,token,z.array(schema));
    output.push(...items);
    if (items.length < 100) return output;
  }
  throw new PublicError(422,'activity_limit','This repository exceeds the import limit. Select fewer repositories or retry a quieter day.');
}
const oauthSchema = z.object({access_token:z.string(), refresh_token:z.string().optional(), expires_in:z.number().optional()});
export async function exchangeGitHub(code: string) {
  const response = await fetch('https://github.com/login/oauth/access_token',{
    method:'POST', headers:{accept:'application/json','Content-Type':'application/json'}, signal:AbortSignal.timeout(15_000),
    body:JSON.stringify({client_id:required('GITHUB_CLIENT_ID'),client_secret:required('GITHUB_CLIENT_SECRET'),
      code,redirect_uri:`${publicURL()}/connect/callback`}),
  });
  if (!response.ok) throw new GitHubError(response.status);
  return oauthSchema.parse(await response.json());
}
export const identity = (token: string) => github('/user',token,githubUser);
export async function accessibleRepositories(token: string): Promise<ConnectedRepository[]> {
  const installations = await pages('/user/installations',token,installationSchema,'installations');
  const result: ConnectedRepository[] = [];
  for (const installation of installations) {
    if (installation.app_id !== Number(required('GITHUB_APP_ID')) || installation.suspended_at) continue;
    if (!['contents','pull_requests','issues'].every(key => ['read','write'].includes(installation.permissions[key]))) continue;
    const repos = await pages(`/user/installations/${installation.id}/repositories`,token,repoSchema,'repositories');
    result.push(...repos.map(repo => ({id:String(repo.id),installationID:String(installation.id),name:repo.name,
      fullName:repo.full_name,url:repo.html_url,description:repo.description ?? '',isPrivate:repo.private,defaultBranch:repo.default_branch})));
  }
  return result;
}
export async function installationToken(repository: ConnectedRepository) {
  const pem = createPrivateKey(required('GITHUB_PRIVATE_KEY').replaceAll('\\n','\n')).export({type:'pkcs8',format:'pem'}).toString();
  const key = await importPKCS8(pem,'RS256');
  const jwt = await new SignJWT({}).setProtectedHeader({alg:'RS256'}).setIssuer(required('GITHUB_APP_ID'))
    .setIssuedAt(Math.floor(Date.now()/1000)-60).setExpirationTime('9m').sign(key);
  const value = await github(`/app/installations/${repository.installationID}/access_tokens`,jwt,z.object({token:z.string()}),{
    method:'POST',body:JSON.stringify({repository_ids:[Number(repository.id)],permissions:{contents:'read',pull_requests:'read',issues:'read'}}),
  });
  return value.token;
}
/** User access tokens revalidate membership; an installation token alone cannot prove user access. */
export async function userToken(userID: string): Promise<string> {
  const sql = db();
  const [user] = await sql`SELECT * FROM users WHERE id=${userID} AND disconnected_at IS NULL`;
  if (!user) throw new PublicError(401,'disconnected','Reconnect GitHub to continue.');
  if (!user.token_expires_at || new Date(user.token_expires_at).getTime()>Date.now()+60_000) return decrypt(user.access_token);
  if (!user.refresh_token) throw new PublicError(401,'expired','Reconnect GitHub to continue.');
  const [locked] = await sql`UPDATE users SET token_refresh_until=now()+interval '30 seconds'
    WHERE id=${userID} AND (token_refresh_until IS NULL OR token_refresh_until<now()) RETURNING id`;
  if (!locked) throw new PublicError(409,'refreshing','GitHub credentials are refreshing. Please retry shortly.');
  try {
    const response = await fetch('https://github.com/login/oauth/access_token',{
      method:'POST',headers:{accept:'application/json','Content-Type':'application/json'},signal:AbortSignal.timeout(15_000),
      body:JSON.stringify({client_id:required('GITHUB_CLIENT_ID'),client_secret:required('GITHUB_CLIENT_SECRET'),
        grant_type:'refresh_token',refresh_token:decrypt(user.refresh_token)}),
    });
    if (!response.ok) throw await githubFailure(response);
    const parsed = oauthSchema.safeParse(await response.json());
    if (!parsed.success) throw new PublicError(401,'github_access','GitHub authorization expired. Reconnect to continue.');
    const value = parsed.data;
    await sql`UPDATE users SET access_token=${encrypt(value.access_token)},
      refresh_token=${value.refresh_token ? encrypt(value.refresh_token) : user.refresh_token},
      token_expires_at=${value.expires_in ? new Date(Date.now()+value.expires_in*1000).toISOString() : null},
      token_refresh_until=NULL WHERE id=${userID} AND disconnected_at IS NULL`;
    return value.access_token;
  } finally { await sql`UPDATE users SET token_refresh_until=NULL WHERE id=${userID}`; }
}
const authorSchema = githubUser.nullable();
const commitSchema = z.object({sha:z.string(),html_url:z.url(),author:authorSchema,committer:authorSchema,
  commit:z.object({message:z.string(),committer:z.object({date:z.string()})})});
const fileSchema = z.object({filename:z.string(),additions:z.number(),deletions:z.number(),patch:z.string().optional()});
const issueSchema = z.object({id:z.number(),number:z.number(),title:z.string(),body:z.string().nullable(),html_url:z.url(),
  user:githubUser,created_at:z.string(),updated_at:z.string(),pull_request:z.unknown().optional()});
const eventSchema = z.object({id:z.number().nullable().optional(),event:z.string(),actor:authorSchema.optional(),created_at:z.string().nullable().optional()}).passthrough();
export function isUserCommit(commit: z.infer<typeof commitSchema>, userID: string) {
  // Both author and committer attribution are explicit IDs, never a display name or arbitrary email.
  return String(commit.author?.id)===userID || String(commit.committer?.id)===userID;
}
export function safeFile(path: string) {
  return !/(^|\/)(\.env[^/]*|\.git|node_modules|vendor|dist|build|.*\.(pem|key|p12|mobileprovision))($|\/)/i.test(path)
    && !/(^|\/)(pnpm-lock\.yaml|package-lock\.json|yarn\.lock|bun\.lockb?|Cargo\.lock|.*\.lock)$/.test(path);
}
export async function collectActivity(repo: ConnectedRepository, token: string, userID: string,
  interval: {start:string;end:string}, includePatches: boolean): Promise<ActivityEvidence[]> {
  const base = `/repos/${repo.fullName.split('/').map(encodeURIComponent).join('/')}`;
  const within = (date: string) => Date.parse(date)>=Date.parse(interval.start) && Date.parse(date)<Date.parse(interval.end);
  const result = new Map<string,ActivityEvidence>();
  const branches = await pages(`${base}/branches`,token,z.object({name:z.string()}));
  if (branches.length>20) throw new PublicError(422,'branch_limit','Choose repositories with at most 20 branches for this release.');
  for (const branch of branches) {
    const query = new URLSearchParams({sha:branch.name,since:interval.start,until:interval.end});
    const commits = await pages(`${base}/commits?${query}`,token,commitSchema);
    for (const commit of commits) {
      if (!isUserCommit(commit,userID) || !within(commit.commit.committer.date)) continue;
      const id = evidenceID(repo.id,'commit',commit.sha);
      if (result.has(id)) continue;
      if (result.size>=200) throw new PublicError(422,'activity_limit','Too much activity for one generation. Choose fewer repositories.');
      const details = await github(`${base}/commits/${commit.sha}`,token,z.object({files:z.array(fileSchema).optional()}));
      result.set(id,{id,repositoryID:repo.id,externalID:commit.sha,kind:'commit',title:commit.commit.message.split('\n')[0].slice(0,1000),
        body:commit.commit.message.slice(0,4000),occurredAt:new Date(commit.commit.committer.date).toISOString(),
        url:commit.html_url,actorID:userID,attribution:String(commit.author?.id)===userID ? 'author' : 'committer',files:(details.files ?? []).filter(file=>safeFile(file.filename)).slice(0,30).map(file=>({
          path:file.filename,additions:file.additions,deletions:file.deletions,patch:includePatches ? (file.patch ?? '').slice(0,2000) : '',
        }))});
    }
  }
  const issues = await pages(`${base}/issues?state=all&since=${encodeURIComponent(interval.start)}&sort=updated&direction=desc`,token,issueSchema);
  for (const issue of issues) {
    const isPR = issue.pull_request !== undefined;
    const kind = isPR ? 'pullRequest' : 'issue';
    const changes: {id:string; title:string; date:string}[] = [];
    if (String(issue.user.id)===userID && within(issue.created_at)) changes.push({id:`${issue.id}:opened`,title:`Opened ${isPR ? 'PR' : 'issue'} #${issue.number}: ${issue.title}`,date:issue.created_at});
    // Updated_at alone proves neither authorship nor what changed. Timeline actors provide attribution.
    const events = await pages(`${base}/issues/${issue.number}/timeline`,token,eventSchema);
    for (const event of events) {
      if (!event.id || !event.created_at || !within(event.created_at) || String(event.actor?.id)!==userID) continue;
      if (!['closed','reopened','merged','renamed'].includes(event.event)) continue;
      changes.push({id:`${issue.id}:${event.event}:${new Date(event.created_at).toISOString()}`,title:`${event.event === 'merged' ? 'Merged' : event.event === 'closed' ? 'Closed' : event.event === 'reopened' ? 'Reopened' : 'Renamed'} ${isPR ? 'PR' : 'issue'} #${issue.number}: ${issue.title}`,date:event.created_at});
    }
    let files: ActivityEvidence['files'] = [];
    if (isPR && changes.length) {
      const changed = await pages(`${base}/pulls/${issue.number}/files`,token,fileSchema);
      files = changed.filter(file=>safeFile(file.filename)).slice(0,30).map(file=>({path:file.filename,additions:file.additions,
        deletions:file.deletions,patch:includePatches ? (file.patch ?? '').slice(0,2000) : ''}));
    }
    for (const change of changes) {
      const id = evidenceID(repo.id,kind,change.id);
      result.set(id,{id,repositoryID:repo.id,externalID:change.id,kind,title:change.title.slice(0,1000),body:(issue.body ?? '').slice(0,4000),
        occurredAt:new Date(change.date).toISOString(),url:issue.html_url,actorID:userID,attribution:'actor',files});
    }
  }
  if (result.size>200) throw new PublicError(422,'activity_limit','Too much activity for one generation. Choose fewer repositories.');
  return [...result.values()];
}
export async function collectContext(repo: ConnectedRepository, token: string): Promise<RepoContext> {
  const base = `/repos/${repo.fullName.split('/').map(encodeURIComponent).join('/')}`;
  const [languages, tree] = await Promise.all([
    github(`${base}/languages`,token,z.record(z.string(),z.number())),
    github(`${base}/contents`,token,z.array(z.object({name:z.string(),type:z.string()}))),
  ]);
  const documents: RepoContext['documents'] = [];
  const paths = ['README.md','Package.swift','package.json','docs/ARCHITECTURE.md'];
  for (const path of paths) {
    const response = await fetch(`https://api.github.com${base}/contents/${path}`,{cache:'no-store',redirect:'error',signal:AbortSignal.timeout(10_000),
      headers:{accept:'application/vnd.github+json',authorization:`Bearer ${token}`,'X-GitHub-Api-Version':'2026-03-10','User-Agent':'Shiplog-Agent'}});
    if (response.status===404) continue;
    if (!response.ok) throw await githubFailure(response);
    const file = z.object({content:z.string(),encoding:z.literal('base64'),size:z.number()}).parse(await response.json());
    if (file.size>64_000) continue;
    documents.push({path,text:Buffer.from(file.content,'base64').toString('utf8').slice(0,4000)});
  }
  return {repositoryID:repo.id,description:repo.description.slice(0,1000),languages:Object.keys(languages).sort(),
    topLevelFiles:tree.map(file=>file.name).filter(safeFile).slice(0,100),documents};
}

export async function collectCommit(repo: ConnectedRepository, token: string, sha: string, userID: string, includePatches: boolean): Promise<ActivityEvidence | null> {
  if (!/^[a-f0-9]{40,64}$/i.test(sha)) return null;
  const base = `/repos/${repo.fullName.split('/').map(encodeURIComponent).join('/')}`;
  const commit = await github(`${base}/commits/${sha}`,token,commitSchema.extend({files:z.array(fileSchema).optional()}));
  if (!isUserCommit(commit,userID)) return null;
  return {id:evidenceID(repo.id,'commit',commit.sha),repositoryID:repo.id,externalID:commit.sha,kind:'commit',
    title:commit.commit.message.split('\n')[0].slice(0,1000),body:commit.commit.message.slice(0,4000),
    occurredAt:new Date(commit.commit.committer.date).toISOString(),url:commit.html_url,actorID:userID,
    attribution:String(commit.author?.id)===userID ? 'author' : 'committer',
    files:(commit.files ?? []).filter(file=>safeFile(file.filename)).slice(0,30).map(file=>({path:file.filename,
      additions:file.additions,deletions:file.deletions,patch:includePatches ? (file.patch ?? '').slice(0,2000) : ''}))};
}
