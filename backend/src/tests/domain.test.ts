import { describe, it, expect, vi } from 'vitest';
import { z } from 'zod';
import { dayInterval, evidenceID, generationHash, validateSynthesis, reconciliationDays, type ActivityEvidence, type SynthesisInput } from '../lib/domain';
import { matchEntries } from '../lib/journal';
import { createHmac } from 'node:crypto';
import { challenge, encrypt, decrypt, verifyWebhook } from '../lib/security';
import { normalizeWebhook } from '../lib/webhooks';
import { safeFile, isUserCommit, github, collectActivity } from '../lib/github';

const evidence: ActivityEvidence = {id:evidenceID('12','commit','abc'),repositoryID:'12',externalID:'abc',kind:'commit',
  title:'Improve onboarding',body:'',occurredAt:'2026-10-05T16:00:00.000Z',url:'https://github.com/test/repo/commit/abc',actorID:'1',files:[]};
const input: SynthesisInput = {day:'2026-10-05',contexts:[{repositoryID:'12',description:'',languages:[],topLevelFiles:[],documents:[]}],evidence:[evidence],existing:[]};
const output = {entries:[{repositoryID:'12',title:'Improved onboarding',detail:'Simplified the connection screen.',kind:'improvement',confidence:0.9,evidenceIDs:[evidence.id]}],
  narrative:{text:'I improved onboarding.',evidenceIDs:[evidence.id]}};

describe('civil days and identity',()=>{
  it('uses 23 and 25 hour DST days',()=>{
    const spring=dayInterval({day:'2026-03-08',timeZone:'America/Chicago'});
    const fall=dayInterval({day:'2026-11-01',timeZone:'America/Chicago'});
    expect(Date.parse(spring.end)-Date.parse(spring.start)).toBe(23*3600*1000);
    expect(Date.parse(fall.end)-Date.parse(fall.start)).toBe(25*3600*1000);
  });
  it('scopes identity by repository and event kind and escapes delimiters',()=>{
    expect(evidenceID('12','issue','42:closed')).toBe('github:12:issue:42%3Aclosed');
    expect(evidenceID('13','issue','42')).not.toBe(evidenceID('12','issue','42'));
    expect(evidenceID('12','pullRequest','42')).not.toBe(evidenceID('12','issue','42'));
  });
  it('backfills missed civil days across DST with a seven-day maximum',()=>{
    expect(reconciliationDays(new Date('2026-03-07T18:00:00Z'),'America/Chicago',new Date('2026-03-09T18:00:00Z'))).toEqual(['2026-03-07','2026-03-08','2026-03-09']);
    expect(reconciliationDays(new Date('2025-01-01T00:00:00Z'),'America/Chicago',new Date('2026-10-05T18:00:00Z'))).toHaveLength(7);
  });
});
describe('synthesis provenance',()=>{
  it('accepts grouped supported work',()=>expect(validateSynthesis(output,input)).toEqual(output));
  it('rejects unknown evidence before publishing',()=>expect(()=>validateSynthesis({...output,entries:[{...output.entries[0],evidenceIDs:['invented']}]},input)).toThrow());
  it('rejects repository mixing, duplicate citations and unsupported narrative',()=>{
    expect(()=>validateSynthesis({...output,entries:[{...output.entries[0],repositoryID:'other'}]},input)).toThrow();
    expect(()=>validateSynthesis({...output,entries:[...output.entries,...output.entries]},input)).toThrow();
    expect(()=>validateSynthesis({...output,narrative:{text:'I shipped',evidenceIDs:[]}},input)).toThrow();
  });
  it('reserves edited work while allowing a narrative to cite saved words',()=>{
    const protectedInput = {...input,existing:[{id:'saved',title:'My words',detail:'',evidenceIDs:[evidence.id],userEdited:true}]};
    expect(()=>validateSynthesis(output,protectedInput)).toThrow('Protected evidence');
    expect(validateSynthesis({...output,entries:[]},protectedInput).entries).toEqual([]);
  });
  it('validates confidence and result bounds',()=>{
    expect(()=>validateSynthesis({...output,entries:[{...output.entries[0],confidence:1.01}]},input)).toThrow();
    expect(()=>validateSynthesis({...output,entries:[]},input)).toThrow();
  });
  it('hashes independent ordering and changes in evidence or edited words',()=>{
    const second = {...evidence,id:'second',externalID:'second'};
    expect(generationHash({...input,evidence:[evidence,second]})).toBe(generationHash({...input,evidence:[second,evidence]}));
    expect(generationHash(input)).not.toBe(generationHash({...input,evidence:[{...evidence,title:'Changed'}]}));
  });
  it('keeps stable work IDs as evidence arrives, never consumes protected entries',()=>{
    const existing = {id:'00000000-0000-4000-8000-000000000001',repositoryID:'12',title:'Old',detail:'',kind:'improvement',confidence:0.8,
      evidenceIDs:[evidence.id],occurredAt:evidence.occurredAt,userEdited:false,userDeleted:false};
    const generated = validateSynthesis(output,input).entries;
    expect(matchEntries(generated,[existing])[0].id).toBe(existing.id);
    expect(matchEntries(generated,[{...existing,userEdited:true}])[0].id).not.toBe(existing.id);
  });
});
describe('security and attribution',()=>{
  it('checks exact raw signed bytes',()=>{
    const raw='{"event":1}';const signature=`sha256=${createHmac('sha256','test-only-secret').update(raw).digest('hex')}`;
    expect(verifyWebhook(raw,signature,'test-only-secret')).toBe(true);
    expect(verifyWebhook(`${raw} `,signature,'test-only-secret')).toBe(false);
    expect(verifyWebhook(raw,null,'test-only-secret')).toBe(false);
  });
  it('encrypts credentials with authenticated encryption',()=>{
    process.env.TOKEN_ENCRYPTION_KEY=Buffer.alloc(32,7).toString('base64');
    const value=encrypt('test-only-token');expect(value).not.toContain('test-only-token');expect(decrypt(value)).toBe('test-only-token');
    const bytes=Buffer.from(value,'base64');bytes[30]^=1;expect(()=>decrypt(bytes.toString('base64'))).toThrow();
  });
  it('binds the mobile verifier to its SHA256 challenge',()=>{
    expect(challenge('test-verifier')).not.toBe(challenge('other-verifier'));
    expect(challenge('test-verifier')).toHaveLength(43);
  });
  it('rejects display-name attribution and filters sensitive paths',()=>{
    const commit={sha:'abc',html_url:'https://github.com/test/repo',author:{id:2,login:'same-name'},committer:null,commit:{message:'test',committer:{date:evidence.occurredAt}}};
    expect(isUserCommit(commit,'1')).toBe(false);expect(isUserCommit(commit,'2')).toBe(true);
    for (const path of ['.env.local','secrets/private.key','vendor/code.swift','pnpm-lock.yaml','package-lock.json']) expect(safeFile(path)).toBe(false);
    expect(safeFile('src/onboarding.swift')).toBe(true);
  });
  it('uses the merge actor rather than PR author, and never infers an update from updated_at',()=>{
    const payload={repository:{id:12},sender:{id:2},action:'closed',pull_request:{id:42,number:42,title:'Change',body:'',html_url:'https://github.com/test/repo/pull/42',
      user:{id:1},created_at:evidence.occurredAt,updated_at:evidence.occurredAt,merged:true,merged_at:evidence.occurredAt,merged_by:{id:2}}};
    const normalized=normalizeWebhook('pull_request',payload);
    expect(normalized?.actorID).toBe('2');expect(normalized?.title).toContain('Merged');
    expect(normalizeWebhook('pull_request',{...payload,action:'edited'})).toBeNull();
  });
  it('distinguishes rate limits from access revocation and retains the retry delay',async()=>{
    const fetch=vi.spyOn(globalThis,'fetch');
    try {
      fetch.mockResolvedValueOnce(new Response(JSON.stringify({message:'API rate limit exceeded'}),{status:403,headers:{'retry-after':'120'}}));
      await expect(github('/test','test-only-token',z.object({}))).rejects.toMatchObject({code:'github_rate_limited',retryAfterSeconds:120});
      fetch.mockResolvedValueOnce(new Response(JSON.stringify({message:'Resource not accessible'}),{status:403}));
      await expect(github('/test','test-only-token',z.object({}))).rejects.toMatchObject({code:'github_access'});
    } finally { fetch.mockRestore(); }
  });
  it('accepts heterogeneous PR timelines without attributing comments or teammate actions',async()=>{
    const fetch=vi.spyOn(globalThis,'fetch');
    const now=new Date().toISOString();
    try {
      fetch.mockImplementation(async url=>{
        const path=new URL(String(url)).pathname;
        const body=path.endsWith('/branches') ? [{name:'main'}]
          : path.endsWith('/commits') || path.endsWith('/files') ? []
          : path.endsWith('/issues') ? [{id:42,number:42,title:'Onboarding',body:'Context',html_url:'https://github.com/test/repo/pull/42',user:{id:2,login:'teammate'},
            created_at:'2026-01-01T00:00:00Z',updated_at:now,pull_request:{}}]
          : [{event:'committed',sha:'abc'}, {event:'commented',id:3,user:{id:1,login:'user'},created_at:now},
            {event:'merged',id:4,actor:{id:1,login:'user'},created_at:now},
            {event:'closed',id:5,actor:{id:2,login:'teammate'},created_at:now}];
        return Response.json(body);
      });
      const result=await collectActivity({id:'12',installationID:'99',name:'Repo',fullName:'test/repo',url:'https://github.com/test/repo',description:'',isPrivate:true,defaultBranch:'main'},
        'test-only-token','1',{start:'2026-01-02T00:00:00Z',end:'2027-01-01T00:00:00Z'},false);
      expect(result).toHaveLength(1);expect(result[0].title).toBe('Merged PR #42: Onboarding');expect(result[0].actorID).toBe('1');
    } finally { fetch.mockRestore(); }
  });
});
