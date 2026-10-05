import { processWebhook } from '@/lib/webhooks';
import { runJob, scheduleDue } from '@/lib/jobs';
import { db } from '@/lib/db';
import { equal, PublicError, required } from '@/lib/security';
import { route } from '@/lib/http';
export const maxDuration = 300;
export function GET(request: Request) { return route(async()=>{
  if (!equal(request.headers.get('authorization') ?? '',`Bearer ${required('CRON_SECRET')}`)) throw new PublicError(401,'unauthorized','Unauthorized.');
  const sql = db();
  await sql.transaction([
    sql`DELETE FROM connect_attempts WHERE expires_at<now()`,sql`DELETE FROM sessions WHERE expires_at<now()`,
    sql`DELETE FROM request_buckets WHERE reset_at<now()`,
    sql`DELETE FROM webhook_deliveries WHERE received_at<now()-interval '7 days'`,
  ]);
  await scheduleDue();
  const start = Date.now(); let processed=0;
  while (Date.now()-start<210_000) {
    const event = await processWebhook(); const job = await runJob();
    if (!event && !job) break;
    processed++;
  }
  return Response.json({processed});
}); }
