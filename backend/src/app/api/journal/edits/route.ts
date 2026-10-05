import { z } from 'zod';
import { after } from 'next/server';
import { authenticate } from '@/lib/auth';
import { applyEdits, editSchema, enqueueEditedJournals } from '@/lib/edits';
import { runJob } from '@/lib/jobs';
import { jsonBody, route } from '@/lib/http';
export const maxDuration = 300;
export function POST(request: Request) { return route(async()=>{
  const user = await authenticate(request);
  const input = z.object({edits:z.array(editSchema).max(50)}).parse(await jsonBody(request,1_100_000));
  const accepted=await applyEdits(user.id,input.edits);
  const jobs=await enqueueEditedJournals(user.id,input.edits.map(edit=>edit.targetID));
  after(async()=>{ for (const id of jobs) await runJob(id); });
  return Response.json({accepted});
}); }
