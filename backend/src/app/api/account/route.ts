import { z } from 'zod';
import { authenticate } from '@/lib/auth';
import { dayRequest } from '@/lib/domain';
import { db } from '@/lib/db';
import { jsonBody, route } from '@/lib/http';
export function GET(request: Request) { return route(async()=>{
  const user = await authenticate(request);
  return Response.json({userID:user.id,login:user.login,timeZone:user.timeZone,finalizeMinute:user.finalizeMinute,includePatches:user.includePatches});
}); }
export function PATCH(request: Request) { return route(async()=>{
  const user = await authenticate(request);
  const input = z.object({timeZone:dayRequest.shape.timeZone,finalizeMinute:z.number().int().min(0).max(1439)}).parse(await jsonBody(request));
  const sql = db();
  await sql`UPDATE users SET time_zone=${input.timeZone},finalize_minute=${input.finalizeMinute},finalized_day=NULL WHERE id=${user.id}`;
  return Response.json({ok:true});
}); }
export function DELETE(request: Request) { return route(async()=>{
  const user = await authenticate(request); const sql = db();
  await sql`DELETE FROM users WHERE id=${user.id}`;
  return Response.json({ok:true});
}); }
