import { authenticate } from '@/lib/auth';
import { db } from '@/lib/db';
import { route } from '@/lib/http';
export function DELETE(request: Request) { return route(async()=>{
  const user = await authenticate(request); const sql = db();
  await sql.transaction([
    sql`UPDATE users SET disconnected_at=now(),access_token='',refresh_token=NULL,token_expires_at=NULL WHERE id=${user.id}`,
    sql`DELETE FROM sessions WHERE user_id=${user.id}`,
    sql`UPDATE repositories SET enabled=false WHERE user_id=${user.id}`,
    sql`DELETE FROM jobs WHERE user_id=${user.id}`,
  ]);
  return Response.json({ok:true});
}); }
