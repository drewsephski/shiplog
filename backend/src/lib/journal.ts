import { randomUUID } from 'node:crypto';
import { db } from './db';
import { dayInterval, PROMPT_VERSION, type DayRequest, type ActivityEvidence, type ConnectedRepository, type RepoContext,
  generationHash, type SynthesisInput, type SynthesisResult } from './domain';
import { accessibleRepositories, userToken, installationToken, collectActivity, collectContext } from './github';
import { PublicError } from './security';
import { OpenRouterJournalSynthesisService, type JournalSynthesisService } from './synthesis';

export interface SavedEntry {
  id:string; repositoryID:string; title:string; detail:string; kind:string; confidence:number;
  evidenceIDs:string[]; occurredAt:string; userEdited:boolean; userDeleted:boolean;
}
/** Greedy overlap reconciliation keeps stable IDs as new evidence joins a work item. */
export function matchEntries(output: SynthesisResult['entries'], existing: SavedEntry[]) {
  const available = new Map(existing.filter(entry=>!entry.userEdited && !entry.userDeleted).map(entry=>[entry.id,entry]));
  return output.map(entry=>{
    const ranked = [...available.values()].filter(saved=>saved.repositoryID===entry.repositoryID)
      .map(saved=>({saved,overlap:saved.evidenceIDs.filter(id=>entry.evidenceIDs.includes(id)).length}))
      .filter(item=>item.overlap>0).sort((a,b)=>b.overlap-a.overlap || a.saved.id.localeCompare(b.saved.id));
    const id = ranked[0]?.saved.id ?? randomUUID();
    available.delete(id);
    return {...entry,id};
  });
}
export async function enqueue(userID: string, input: DayRequest) {
  const sql = db();
  const [job] = await sql`INSERT INTO jobs(user_id,day,time_zone) VALUES(${userID},${input.day},${input.timeZone})
    ON CONFLICT(user_id,day,time_zone) DO UPDATE SET requested_at=now(),
      status=CASE WHEN jobs.status='running' AND jobs.lease_until>now() THEN jobs.status ELSE 'pending' END,
      available_at=CASE WHEN jobs.status='running' AND jobs.lease_until>now() THEN jobs.available_at ELSE now() END RETURNING id`;
  return job.id as string;
}
const saved = (entry: Record<string, unknown>): SavedEntry => ({
  id:String(entry.id),repositoryID:String(entry.repository_id),title:String(entry.title),detail:String(entry.detail),
  kind:String(entry.kind),confidence:Number(entry.confidence),evidenceIDs:entry.evidence_ids as string[],
  occurredAt:new Date(String(entry.occurred_at)).toISOString(),userEdited:Boolean(entry.user_edited),userDeleted:Boolean(entry.user_deleted),
});
export async function generate(userID: string, input: DayRequest, lease: {jobID:string;token:string},
  service: JournalSynthesisService = new OpenRouterJournalSynthesisService()) {
  const sql = db();
  const [user] = await sql`SELECT * FROM users WHERE id=${userID} AND disconnected_at IS NULL`;
  if (!user) throw new PublicError(401,'disconnected','GitHub was disconnected.');
  const access = await userToken(userID);
  const identityRepos = await accessibleRepositories(access);
  const repositoryRows = await sql`SELECT * FROM repositories WHERE user_id=${userID} AND enabled=true ORDER BY id`;
  if (repositoryRows.length===0) throw new PublicError(409,'no_repositories','Choose repositories in Connect GitHub.');
  const contexts: RepoContext[] = [];
  const interval = dayInterval(input);
  for (const row of repositoryRows) {
    const repo = identityRepos.find(candidate=>candidate.id===row.id && candidate.installationID===row.installation_id);
    if (!repo) {
      await sql`UPDATE repositories SET enabled=false WHERE user_id=${userID} AND id=${row.id}`;
      throw new PublicError(403,'github_access','Repository access changed. Reconnect GitHub to review your selection.');
    }
    const token = await installationToken(repo);
    const context: RepoContext = row.context && row.context_updated_at && new Date(row.context_updated_at).getTime()>Date.now()-86_400_000
      ? row.context : await collectContext(repo,token);
    const evidence = await collectActivity(repo,token,user.github_id,interval,user.include_patches);
    contexts.push(context);
    await sql.transaction([
      sql`UPDATE repositories SET context=${JSON.stringify(context)}::jsonb,context_updated_at=now(),checkpoint=now(),descriptor=${JSON.stringify(repo)}::jsonb
        WHERE user_id=${userID} AND id=${repo.id} AND enabled=true`,
      ...evidence.map(item=>sql`INSERT INTO evidence(user_id,id,repository_id,occurred_at,payload)
        SELECT ${userID},${item.id},${item.repositoryID},${item.occurredAt},${JSON.stringify(item)}::jsonb
        WHERE EXISTS(SELECT 1 FROM users WHERE id=${userID} AND disconnected_at IS NULL)
        ON CONFLICT(user_id,id) DO UPDATE SET payload=EXCLUDED.payload,occurred_at=EXCLUDED.occurred_at`),
    ]);
  }
  const rows = await sql`SELECT e.payload FROM evidence e JOIN repositories r ON r.user_id=e.user_id AND r.id=e.repository_id
    WHERE e.user_id=${userID} AND r.enabled=true AND e.occurred_at>=${interval.start} AND e.occurred_at<${interval.end} ORDER BY e.id`;
  const evidence = rows.map(row=>row.payload as ActivityEvidence);
  if (evidence.length>200) throw new PublicError(422,'activity_limit','Select fewer repositories; this day exceeds the 200-event generation limit.');
  const [journal] = await sql`INSERT INTO journals(user_id,day,time_zone) VALUES(${userID},${input.day},${input.timeZone})
    ON CONFLICT(user_id,day,time_zone) DO UPDATE SET day=EXCLUDED.day RETURNING *`;
  const existing = (await sql`SELECT * FROM entries WHERE journal_id=${journal.id} AND (retired=false OR user_edited=true OR user_deleted=true) ORDER BY id`).map(saved);
  // Deletes suppress their original evidence on every later generation. Edits reserve their evidence.
  const deletedEvidence = new Set(existing.filter(entry=>entry.userDeleted).flatMap(entry=>entry.evidenceIDs));
  const synthesisInput: SynthesisInput = {day:input.day,contexts,evidence:evidence.filter(item=>!deletedEvidence.has(item.id)),
    existing:existing.filter(entry=>!entry.userDeleted).map(entry=>({id:entry.id,title:entry.title,detail:entry.detail,evidenceIDs:entry.evidenceIDs,userEdited:entry.userEdited}))};
  const evidenceHash = generationHash(synthesisInput);
  if (journal.evidence_hash===evidenceHash && journal.prompt_version===PROMPT_VERSION) return;
  const [run] = await sql`INSERT INTO generation_runs(journal_id,evidence_hash,prompt_version) VALUES(${journal.id},${evidenceHash},${PROMPT_VERSION})
    ON CONFLICT(journal_id,evidence_hash,prompt_version) DO UPDATE SET started_at=now() RETURNING id`;
  const output = synthesisInput.evidence.length ? await service.synthesize(synthesisInput) : {entries:[],narrative:{text:'',evidenceIDs:[]}};
  const matches = matchEntries(output.entries,existing);
  // A lease token fences results from interrupted workers. Manual edits are protected at commit time too.
  await sql.transaction([
    sql`SELECT id FROM jobs WHERE id=${lease.jobID} AND lease_token=${lease.token} AND lease_until>now() FOR UPDATE`,
    sql`UPDATE entries SET retired=true WHERE journal_id=${journal.id} AND user_edited=false AND user_deleted=false
      AND EXISTS(SELECT 1 FROM jobs WHERE id=${lease.jobID} AND lease_token=${lease.token} AND lease_until>now())`,
    ...matches.map(entry=>{
      const occurredAt = synthesisInput.evidence.filter(item=>entry.evidenceIDs.includes(item.id)).map(item=>item.occurredAt).sort().at(-1)!;
      return sql`INSERT INTO entries(id,journal_id,repository_id,title,detail,kind,confidence,evidence_ids,occurred_at)
        SELECT ${entry.id},${journal.id},${entry.repositoryID},${entry.title},${entry.detail},${entry.kind},${entry.confidence},${JSON.stringify(entry.evidenceIDs)}::jsonb,${occurredAt}
        WHERE EXISTS(SELECT 1 FROM jobs WHERE id=${lease.jobID} AND lease_token=${lease.token} AND lease_until>now())
        AND EXISTS(SELECT 1 FROM users WHERE id=${userID} AND disconnected_at IS NULL)
        ON CONFLICT(id) DO UPDATE SET title=EXCLUDED.title,detail=EXCLUDED.detail,kind=EXCLUDED.kind,confidence=EXCLUDED.confidence,
          evidence_ids=EXCLUDED.evidence_ids,occurred_at=EXCLUDED.occurred_at,retired=false WHERE entries.user_edited=false AND entries.user_deleted=false`;
    }),
    sql`UPDATE journals SET evidence_hash=${evidenceHash},prompt_version=${PROMPT_VERSION},generated_at=now(),
      narrative=CASE WHEN narrative_edited OR narrative_deleted THEN narrative ELSE ${output.narrative.text} END,
      narrative_evidence_ids=CASE WHEN narrative_edited OR narrative_deleted THEN narrative_evidence_ids ELSE ${JSON.stringify(output.narrative.evidenceIDs)}::jsonb END
      WHERE id=${journal.id} AND EXISTS(SELECT 1 FROM jobs WHERE id=${lease.jobID} AND lease_token=${lease.token} AND lease_until>now())
      AND EXISTS(SELECT 1 FROM users WHERE id=${userID} AND disconnected_at IS NULL)`,
    sql`UPDATE generation_runs SET completed_at=now() WHERE id=${run.id}
      AND EXISTS(SELECT 1 FROM jobs WHERE id=${lease.jobID} AND lease_token=${lease.token} AND lease_until>now())`,
  ]);
}
export async function readJournal(userID: string, input: DayRequest) {
  const sql = db();
  const [journal] = await sql`SELECT * FROM journals WHERE user_id=${userID} AND day=${input.day} AND time_zone=${input.timeZone}`;
  const [job] = await sql`SELECT status,error_code FROM jobs WHERE user_id=${userID} AND day=${input.day} AND time_zone=${input.timeZone}`;
  const repos = await sql`SELECT descriptor,checkpoint,enabled FROM repositories WHERE user_id=${userID} ORDER BY id`;
  const entries = journal ? (await sql`SELECT * FROM entries WHERE journal_id=${journal.id} AND retired=false AND user_deleted=false ORDER BY occurred_at,id`).map(saved) : [];
  const ids = [...new Set([...entries.flatMap(entry=>entry.evidenceIDs), ...(journal?.narrative_evidence_ids ?? []) as string[]])];
  const sources = ids.length ? await sql`SELECT payload FROM evidence WHERE user_id=${userID} AND id=ANY(${ids}::text[]) ORDER BY id` : [];
  return {userID,day:input.day,timeZone:input.timeZone,status:job?.status ?? 'idle',errorCode:job?.error_code ?? null,
    repositories:repos.map(row=>({...row.descriptor as ConnectedRepository,isEnabled:row.enabled,checkpoint:row.checkpoint ? new Date(row.checkpoint).toISOString() : null})),
    entries,evidence:sources.map(row=>row.payload as ActivityEvidence),
    narrative:journal ? {id:journal.id,text:journal.narrative_deleted ? '' : journal.narrative,userEdited:journal.narrative_edited,
      evidenceIDs:journal.narrative_evidence_ids as string[]} : null,
    generation:journal?.generated_at ? {id:journal.id,evidenceHash:journal.evidence_hash,promptVersion:journal.prompt_version,
      generatedAt:new Date(journal.generated_at).toISOString()} : null};
}
