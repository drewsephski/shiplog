import { z } from 'zod';
import { db } from '@/lib/db';
import { hash } from '@/lib/domain';
import { challenge, PublicError, randomToken } from '@/lib/security';
import { jsonBody, route } from '@/lib/http';
export function POST(request: Request) { return route(async()=>{
  const input = z.object({code:z.string().regex(/^[A-Za-z0-9_-]{43}$/),verifier:z.string().regex(/^[A-Za-z0-9_-]{43,128}$/)}).parse(await jsonBody(request));
  const token = randomToken(); const sql = db();
  const [user] = await sql`WITH consumed AS (
    UPDATE connect_attempts SET consumed_at=now() WHERE code_hash=${hash(input.code)} AND challenge=${challenge(input.verifier)}
      AND expires_at>now() AND consumed_at IS NULL RETURNING user_id
  ), issued AS (
    INSERT INTO sessions(token_hash,user_id) SELECT ${hash(token)},user_id FROM consumed RETURNING user_id
  ) SELECT u.id,u.login,u.time_zone,u.finalize_minute,u.include_patches FROM issued JOIN users u ON u.id=issued.user_id`;
  if (!user) throw new PublicError(400,'invalid_code','The connection expired. Restart Connect GitHub.');
  return Response.json({token,userID:user.id,login:user.login,timeZone:user.time_zone,finalizeMinute:user.finalize_minute,includePatches:user.include_patches});
}); }
