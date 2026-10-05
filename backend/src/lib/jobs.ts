import { randomUUID } from 'node:crypto';
import { db } from './db';
import { localDay, localMinute, reconciliationDays } from './domain';
import { enqueue, generate } from './journal';
import { PublicError } from './security';
import type { JournalSynthesisService } from './synthesis';
export async function runJob(id?: string, service?: JournalSynthesisService) {
  const sql = db(); const token = randomUUID();
  const [job] = await sql`UPDATE jobs SET status='running',lease_until=now()+interval '5 minutes',lease_token=${token},
    claimed_at=now(),attempts=attempts+1,error_code=NULL WHERE id=(SELECT id FROM jobs
      WHERE (${id ?? null}::uuid IS NULL OR id=${id ?? null}::uuid)
      AND ((status='pending' AND available_at<=now()) OR (status='running' AND lease_until<now()))
      ORDER BY requested_at LIMIT 1 FOR UPDATE SKIP LOCKED) RETURNING *,day::text AS local_day`;
  if (!job) return false;
  try {
    await generate(job.user_id,{day:job.local_day,timeZone:job.time_zone},{jobID:job.id,token},service);
    await sql`UPDATE jobs SET status=CASE WHEN requested_at>claimed_at THEN 'pending' ELSE 'completed' END,
      lease_until=NULL,lease_token=NULL,attempts=0 WHERE id=${job.id} AND lease_token=${token}`;
    return true;
  } catch(error) {
    const code = error instanceof PublicError ? error.code : 'service_failure';
    const retry=error instanceof PublicError ? error.retryAfterSeconds : 300;
    await sql`UPDATE jobs SET status=CASE WHEN attempts>=5 OR ${code} IN ('github_access','activity_limit','context_limit','branch_limit','no_repositories','disconnected') THEN 'failed' ELSE 'pending' END,
      available_at=now()+${retry}*interval '1 second',lease_until=NULL,lease_token=NULL,error_code=${code} WHERE id=${job.id} AND lease_token=${token}`;
    if (id) throw error;
    return false;
  }
}
export async function scheduleDue(now = new Date()) {
  const sql = db();
  const users = await sql`SELECT id,time_zone,finalize_minute,finalized_day::text AS finalized_day FROM users WHERE disconnected_at IS NULL
    AND finalized_day IS DISTINCT FROM (${now.toISOString()}::timestamptz AT TIME ZONE time_zone)::date
    AND (EXTRACT(HOUR FROM ${now.toISOString()}::timestamptz AT TIME ZONE time_zone)*60
      + EXTRACT(MINUTE FROM ${now.toISOString()}::timestamptz AT TIME ZONE time_zone))>=finalize_minute
    AND EXISTS(SELECT 1 FROM repositories r WHERE r.user_id=users.id AND r.enabled=true) ORDER BY id LIMIT 500`;
  for (const user of users) {
    const day = localDay(user.time_zone,now);
    if (localMinute(user.time_zone,now)<user.finalize_minute || String(user.finalized_day ?? '').slice(0,10)===day) continue;
    await enqueue(user.id,{day,timeZone:user.time_zone});
    await sql`UPDATE users SET finalized_day=${day} WHERE id=${user.id}`;
  }
  // A phone need not be open: reconciliation also runs once a day, regardless of webhook delivery.
  const reconcile = await sql`SELECT u.id,u.time_zone,u.created_at,
    (SELECT MIN(checkpoint) FROM repositories r WHERE r.user_id=u.id AND r.enabled=true) AS checkpoint
    FROM users u WHERE u.disconnected_at IS NULL AND EXISTS(
    SELECT 1 FROM repositories r WHERE r.user_id=u.id AND r.enabled=true AND (r.checkpoint IS NULL OR r.checkpoint<now()-interval '6 hours'))
    AND NOT EXISTS(SELECT 1 FROM jobs j WHERE j.user_id=u.id AND (j.status='pending' OR (j.status='running' AND j.lease_until>now())))
    ORDER BY u.id LIMIT 100`;
  for (const user of reconcile) {
    const since=new Date(user.checkpoint ?? user.created_at);
    for (const day of reconciliationDays(since,user.time_zone,now)) await enqueue(user.id,{day,timeZone:user.time_zone});
  }
}
