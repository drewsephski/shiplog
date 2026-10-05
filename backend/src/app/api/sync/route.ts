import { authenticate, rateLimit } from '@/lib/auth';
import { dayRequest, localDay } from '@/lib/domain';
import { enqueue, readJournal } from '@/lib/journal';
import { runJob } from '@/lib/jobs';
import { PublicError } from '@/lib/security';
import { jsonBody, route } from '@/lib/http';
export const maxDuration = 300;
export function POST(request: Request) { return route(async()=>{
  const user = await authenticate(request);
  const input = dayRequest.parse(await jsonBody(request));
  if (input.day!==localDay(input.timeZone)) throw new PublicError(400,'current_day_required','Sync the current local day.');
  await rateLimit(`sync:${user.id}`,12,3600);
  const id = await enqueue(user.id,input);
  await runJob(id);
  return Response.json(await readJournal(user.id,input));
}); }
