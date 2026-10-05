import { beforeAll, afterAll, beforeEach, describe, it, expect, vi } from 'vitest';
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { installPostgresTransport } from './postgres';
import { db } from '../lib/db';
import { hash, localDay, evidenceID, type ActivityEvidence, type SynthesisInput } from '../lib/domain';
import { challenge, encrypt } from '../lib/security';
import { authenticate } from '../lib/auth';
import { enqueue, readJournal, generate } from '../lib/journal';
import { applyEdits } from '../lib/edits';
import { receiveWebhook } from '../lib/webhooks';
import { POST as exchange } from '../app/api/connect/exchange/route';
import { DELETE as disconnect } from '../app/api/connection/route';

const control = vi.hoisted(()=>({evidence:[] as unknown[],available:true}));
vi.mock('../lib/github',()=>({
  userToken:vi.fn(async()=> 'test-only-token'),installationToken:vi.fn(async()=> 'test-only-installation'),
  accessibleRepositories:vi.fn(async()=>control.available ? [{id:'12',installationID:'99',name:'Repo',fullName:'test/repo',url:'https://github.com/test/repo',description:'',isPrivate:true,defaultBranch:'main'}] : []),
  collectActivity:vi.fn(async()=>control.evidence),collectContext:vi.fn(async()=>({repositoryID:'12',description:'',languages:[],topLevelFiles:[],documents:[]})),
}));

const testURL=process.env.TEST_DATABASE_URL;
describe.skipIf(!testURL)('agent on real PostgreSQL',()=>{
  let transport: ReturnType<typeof installPostgresTransport>;
  let userID:string;
  const day={day:localDay('America/Chicago'),timeZone:'America/Chicago'};
  const verifier='a'.repeat(43);
  const code='b'.repeat(43);
  const token='c'.repeat(43);
  let evidence:ActivityEvidence;
  beforeAll(async()=>{
    transport=installPostgresTransport(testURL!);
    process.env.DATABASE_URL=testURL;
    process.env.TOKEN_ENCRYPTION_KEY=Buffer.alloc(32,5).toString('base64');
    const migration=await readFile(new URL('../../migrations/001_agent.sql',import.meta.url),'utf8');
    await transport.pool.query(migration);
  });
  afterAll(async()=>await transport?.close());
  beforeEach(async()=>{
    // The harness URL must refer to an isolated throwaway database.
    await transport.pool.query('TRUNCATE users,webhook_deliveries,request_buckets CASCADE');
    control.available=true;
    const sql=db();
    const [user]=await sql`INSERT INTO users(github_id,login,time_zone,access_token) VALUES('1','test','America/Chicago',${encrypt('test-only-token')}) RETURNING id`;
    userID=user.id;
    await sql`INSERT INTO repositories(user_id,id,installation_id,descriptor) VALUES(${userID},'12','99',${JSON.stringify({id:'12',installationID:'99',name:'Repo',fullName:'test/repo',url:'https://github.com/test/repo',description:'',isPrivate:true,defaultBranch:'main'})}::jsonb)`;
    evidence={id:evidenceID('12','commit','a'.repeat(40)),repositoryID:'12',externalID:'a'.repeat(40),kind:'commit',title:'Improve onboarding',body:'',
      occurredAt:new Date().toISOString(),url:`https://github.com/test/repo/commit/${'a'.repeat(40)}`,actorID:'1',files:[]};
    control.evidence=[evidence];
  });
  async function lease() {
    const jobID=await enqueue(userID,day);const token=randomUUID();const sql=db();
    await sql`UPDATE jobs SET status='running',lease_until=now()+interval '5 minutes',lease_token=${token} WHERE id=${jobID}`;
    return {jobID,token};
  }
  const service={async synthesize(input:SynthesisInput){
    const reserved=new Set(input.existing.filter(entry=>entry.userEdited).flatMap(entry=>entry.evidenceIDs));
    const selected=input.evidence.filter(item=>!reserved.has(item.id));
    return {entries:selected.length ? [{repositoryID:'12',title:'Improved onboarding',detail:'Simplified connection.',kind:'improvement' as const,confidence:0.9,evidenceIDs:selected.map(item=>item.id)}] : [],
      narrative:{text:'I worked on onboarding.',evidenceIDs:input.evidence.map(item=>item.id)}};
  }};
  it('consumes the PKCE exchange once and scopes sessions to a verified user',async()=>{
    const sql=db();
    await sql`INSERT INTO connect_attempts(state_hash,challenge,time_zone,code_hash,user_id) VALUES('state',${challenge(verifier)},${day.timeZone},${hash(code)},${userID})`;
    const request=(candidate:string)=>new Request('https://agent.test/api/connect/exchange',{method:'POST',body:JSON.stringify({code,verifier:candidate})});
    expect((await exchange(request('z'.repeat(43)))).status).toBe(400);
    const response=await exchange(request(verifier));expect(response.status).toBe(200);
    const session=await response.json();expect(session.userID).toBe(userID);
    expect((await exchange(request(verifier))).status).toBe(400);
    const user=await authenticate(new Request('https://agent.test',{headers:{authorization:`Bearer ${session.token}`}}));
    expect(user.id).toBe(userID);
  });
  it('generates once per evidence hash, keeps IDs on incremental updates, and preserves edits/deletes',async()=>{
    const synthesize=vi.fn(service.synthesize);
    await generate(userID,day,await lease(),{synthesize});
    let journal=await readJournal(userID,day);expect(journal.entries).toHaveLength(1);const id=journal.entries[0].id;
    await generate(userID,day,await lease(),{synthesize});expect(synthesize).toHaveBeenCalledTimes(1);
    control.evidence=[evidence,{...evidence,id:evidenceID('12','commit','d'.repeat(40)),externalID:'d'.repeat(40)}];
    await generate(userID,day,await lease(),{synthesize});journal=await readJournal(userID,day);expect(journal.entries[0].id).toBe(id);
    const mutationID=randomUUID();
    await applyEdits(userID,[{mutationID,targetID:id,targetType:'entry',deleted:false,title:'My precise words',detail:'An honest description',kind:'improvement',occurredAt:evidence.occurredAt}]);
    await generate(userID,day,await lease(),{synthesize});journal=await readJournal(userID,day);expect(journal.entries[0].title).toBe('My precise words');
    await applyEdits(userID,[{mutationID:randomUUID(),targetID:id,targetType:'entry',deleted:true}]);
    await generate(userID,day,await lease(),{synthesize});expect((await readJournal(userID,day)).entries).toHaveLength(0);
  });
  it('makes outbox retries idempotent and rejects cross-account mutations',async()=>{
    await generate(userID,day,await lease(),service);const journal=await readJournal(userID,day);const id=journal.entries[0].id;
    const edit={mutationID:randomUUID(),targetID:id,targetType:'entry' as const,deleted:false,title:'First',detail:'',kind:'fix' as const,occurredAt:evidence.occurredAt};
    await applyEdits(userID,[edit]);await applyEdits(userID,[{...edit,mutationID:randomUUID(),title:'Second'}]);await applyEdits(userID,[edit]);
    expect((await readJournal(userID,day)).entries[0].title).toBe('Second');
    await expect(applyEdits(randomUUID(),[edit])).rejects.toThrow('no longer available');
  });
  it('fences expired workers and blocks generation after access revocation',async()=>{
    const old=await lease();const sql=db();await sql`UPDATE jobs SET lease_until=now()-interval '1 second' WHERE id=${old.jobID}`;
    await generate(userID,day,old,service);expect((await readJournal(userID,day)).generation).toBeNull();
    control.available=false;
    await expect(generate(userID,day,await lease(),service)).rejects.toThrow('Repository access changed');
    expect((await sql`SELECT enabled FROM repositories WHERE user_id=${userID}`)[0].enabled).toBe(false);
  });
  it('deduplicates deliveries and attributes teammate issue actions separately',async()=>{
    const payload={installation:{id:99},repository:{id:12},sender:{id:2},action:'opened',issue:{id:42,number:42,title:'Issue',body:'',html_url:'https://github.com/test/repo/issues/42',
      user:{id:2},created_at:evidence.occurredAt,updated_at:evidence.occurredAt}};
    await receiveWebhook('delivery-one','issues',payload);await receiveWebhook('delivery-one','issues',payload);
    const sql=db();expect((await sql`SELECT * FROM webhook_deliveries`)).toHaveLength(1);expect(await sql`SELECT * FROM evidence`).toHaveLength(0);
    await receiveWebhook('delivery-two','issues',{...payload,sender:{id:1},issue:{...payload.issue,user:{id:1}}});
    expect(await sql`SELECT * FROM evidence`).toHaveLength(1);
    await receiveWebhook('ignored','issues',{...payload,repository:{id:777}});expect(await sql`SELECT * FROM webhook_deliveries`).toHaveLength(2);
  });
  it('disconnect stops scheduled work and removes credentials and bearer sessions',async()=>{
    const sql=db();await sql`INSERT INTO sessions(token_hash,user_id) VALUES(${hash(token)},${userID})`;
    await enqueue(userID,day);
    const response=await disconnect(new Request('https://agent.test/api/connection',{method:'DELETE',headers:{authorization:`Bearer ${token}`}}));
    expect(response.status).toBe(200);expect(await sql`SELECT * FROM jobs`).toHaveLength(0);expect(await sql`SELECT * FROM sessions`).toHaveLength(0);
    expect((await sql`SELECT access_token FROM users WHERE id=${userID}`)[0].access_token).toBe('');
  });
});
