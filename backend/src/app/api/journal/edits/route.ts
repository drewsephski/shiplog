import { z } from 'zod';
import { authenticate } from '@/lib/auth';
import { applyEdits, editSchema } from '@/lib/edits';
import { jsonBody, route } from '@/lib/http';
export function POST(request: Request) { return route(async()=>{
  const user = await authenticate(request);
  const input = z.object({edits:z.array(editSchema).max(50)}).parse(await jsonBody(request,1_100_000));
  return Response.json({accepted:await applyEdits(user.id,input.edits)});
}); }
