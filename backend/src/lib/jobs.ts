import { randomUUID } from 'node:crypto';
import { db } from './db';
import { localDay, localMinute } from './domain';
import { enqueue, generate } from './journal';
import { PublicError } from './security';
export async function runJob(id?: string) {
  const sql = db(); const token = randomUUID();
  const [job] = await sql`UPDATE jobs SET status='running',lease_until=now()+interval '5 minutes',lease_token=${token},
    claimed_at=now(),attempts=attempts+1,error_code=NULL WHERE id=(SELECT id FROM jobs
      WHERE (${id ?? null}::uuid IS NULL OR id=${id ?? null}::uuid)
      AND ((status='pending' AND available_at<=now()) OR (status='running' AND lease_until<now()))
      ORDER BY requested_at LIMIT 1 FOR UPDATE SKIP LOCKED) RETURNING *`;
  if (!job) return false;
  try {
    await generate(job.user_id,{day:String(job.day).slice(0,10),timeZone:job.time_zone},{jobID:job.id,token});
    await sql`UPDATE jobs SET status=CASE WHEN requested_at>claimed_at THEN 'pending' ELSE 'completed' END,
      lease_until=NULL,lease_token=NULL,attempts=0 WHERE id=${job.id} AND lease_token=${token}`;
    return true;
  } catch(error) {
    const code = error instanceof PublicError ? error.code : 'service_failure';
    await sql`UPDATE jobs SET status=CASE WHEN attempts>=5 OR ${code} IN ('github_access','activity_limit','branch_limit','no_repositories','disconnected') THEN 'failed' ELSE 'pending' END,
      available_at=now()+interval '5 minutes',lease_until=NULL,lease_token=NULL,error_code=${code} WHERE id=${job.id} AND lease_token=${token}`;
    if (id) throw error;
    return false;
  }
}
export async function scheduleDue(now = new Date()) {
  const sql = db();
  const users = await sql`SELECT id,time_zone,finalize_minute,finalized_day FROM users WHERE disconnected_at IS NULL
    AND EXISTS(SELECT 1 FROM repositories r WHERE r.user_id=users.id AND r.enabled=true) LIMIT 500`;
  for (const user of users) {
    const day = localDay(user.time_zone,now);
    if (localMinute(user.time_zone,now)<user.finalize_minute || String(user.finalized_day ?? '').slice(0,10)===day) continue;
    await enqueue(user.id,{day,timeZone:user.time_zone});
    await sql`UPDATE users SET finalized_day=${day} WHERE id=${user.id}`;
  }
  // A phone need not be open: reconciliation also runs once a day, regardless of webhook delivery.
  const reconcile = await sql`SELECT u.id,u.time_zone FROM users u WHERE u.disconnected_at IS NULL AND EXISTS(
    SELECT 1 FROM repositories r WHERE r.user_id=u.id AND r.enabled=true AND (r.checkpoint IS NULL OR r.checkpoint<now()-interval '6 hours')) LIMIT 100`;
  for (const user of reconcile) await enqueue(user.id,{day:localDay(user.time_zone,now),timeZone:user.time_zone});
}
