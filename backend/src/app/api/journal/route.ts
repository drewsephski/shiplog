import { authenticate } from '@/lib/auth';
import { dayRequest } from '@/lib/domain';
import { readJournal } from '@/lib/journal';
import { route } from '@/lib/http';
export function GET(request: Request) { return route(async()=>{
  const user = await authenticate(request);
  const input = dayRequest.parse(Object.fromEntries(new URL(request.url).searchParams));
  return Response.json(await readJournal(user.id,input));
}); }
