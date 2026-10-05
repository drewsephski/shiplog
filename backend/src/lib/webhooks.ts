import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import { db } from './db';
import { evidenceID, localDay, type ActivityEvidence, type ConnectedRepository } from './domain';
import { collectCommit, installationToken, accessibleRepositories, userToken } from './github';
import { enqueue } from './journal';
import { PublicError } from './security';

const actor = z.object({id:z.number()});
const item = z.object({id:z.number(),number:z.number(),title:z.string(),body:z.string().nullable(),html_url:z.url(),
  user:actor,created_at:z.string(),updated_at:z.string(),closed_at:z.string().nullable().optional(),
  merged:z.boolean().optional(),merged_at:z.string().nullable().optional(),merged_by:actor.nullable().optional()});
const payloadSchema = z.object({
  action:z.string().optional(),installation:z.object({id:z.number()}).optional(),
  repository:z.object({id:z.number()}).optional(),sender:actor.optional(),
  commits:z.array(z.object({id:z.string()})).max(2048).optional(),
  issue:item.optional(),pull_request:item.optional(),
  repositories_removed:z.array(z.object({id:z.number()})).optional(),
});
export type WebhookPayload = z.infer<typeof payloadSchema>;
export function normalizeWebhook(event: string, payload: WebhookPayload): ActivityEvidence | null {
  const subject = event==='issues' ? payload.issue : event==='pull_request' ? payload.pull_request : undefined;
  if (!subject || !payload.repository) return null;
  const merged = event==='pull_request' && payload.action==='closed' && subject.merged;
  const action = merged ? 'merged' : payload.action;
  if (!action || !['opened','closed','reopened'].includes(action) && action!=='merged') return null;
  const actorID = action==='opened' ? subject.user.id : merged ? subject.merged_by?.id : payload.sender?.id;
  if (!actorID) return null;
  const date = action==='opened' ? subject.created_at : merged ? subject.merged_at : action==='closed' ? subject.closed_at : subject.updated_at;
  if (!date) return null;
  const occurredAt = new Date(date).toISOString();
  const kind = event==='issues' ? 'issue' : 'pullRequest';
  const externalID = action==='opened' ? `${subject.id}:opened` : `${subject.id}:${action}:${occurredAt}`;
  return {id:evidenceID(String(payload.repository.id),kind,externalID),repositoryID:String(payload.repository.id),externalID,kind,
    title:`${action==='opened' ? 'Opened' : action==='merged' ? 'Merged' : action==='closed' ? 'Closed' : 'Reopened'} ${kind==='issue' ? 'issue' : 'PR'} #${subject.number}: ${subject.title}`.slice(0,1000),
    body:(subject.body ?? '').slice(0,4000),url:subject.html_url,occurredAt,actorID:String(actorID),files:[]};
}
export async function receiveWebhook(id: string, event: string, raw: unknown) {
  const payload = payloadSchema.parse(raw); const sql = db();
  if (event==='installation' && ['deleted','suspend'].includes(payload.action ?? '')) {
    await sql`UPDATE repositories SET enabled=false WHERE installation_id=${String(payload.installation?.id)}`;
    return;
  }
  if (event==='installation_repositories' && payload.repositories_removed?.length) {
    await sql`UPDATE repositories SET enabled=false WHERE installation_id=${String(payload.installation?.id)}
      AND id=ANY(${payload.repositories_removed.map(repo=>String(repo.id))}::text[])`;
    return;
  }
  // Unselected repositories never enter our durable event store.
  if (!payload.repository || !payload.installation || !['push','pull_request','issues'].includes(event)) return;
  const repositories = await sql`SELECT r.user_id,u.github_id FROM repositories r JOIN users u ON r.user_id=u.id
    WHERE r.id=${String(payload.repository.id)} AND r.installation_id=${String(payload.installation.id)} AND r.enabled=true AND u.disconnected_at IS NULL`;
  if (!repositories.length) return;
  const evidence = normalizeWebhook(event,payload);
  const compact = {installation:payload.installation,repository:payload.repository,commits:payload.commits ?? []};
  await sql.transaction([
    sql`INSERT INTO webhook_deliveries(id,event,payload) VALUES(${id},${event},${JSON.stringify(compact)}::jsonb) ON CONFLICT DO NOTHING`,
    ...repositories.filter(repo=>evidence && repo.github_id===evidence.actorID).map(repo=>sql`
      INSERT INTO evidence(user_id,id,repository_id,occurred_at,payload)
      VALUES(${repo.user_id},${evidence!.id},${evidence!.repositoryID},${evidence!.occurredAt},${JSON.stringify(evidence)}::jsonb)
      ON CONFLICT(user_id,id) DO NOTHING`),
  ]);
}
export async function processWebhook() {
  const sql = db(); const lease = randomUUID();
  const [delivery] = await sql`UPDATE webhook_deliveries SET status='running',lease_until=now()+interval '5 minutes',lease_token=${lease},attempts=attempts+1
    WHERE id=(SELECT id FROM webhook_deliveries WHERE (status='pending' OR (status='running' AND lease_until<now()))
      AND attempts<5 ORDER BY received_at LIMIT 1 FOR UPDATE SKIP LOCKED) RETURNING *`;
  if (!delivery) return false;
  try {
    const payload = payloadSchema.parse(delivery.payload);
    const repos = await sql`SELECT r.*,u.github_id,u.time_zone,u.include_patches FROM repositories r JOIN users u ON r.user_id=u.id
      WHERE r.id=${String(payload.repository?.id)} AND r.installation_id=${String(payload.installation?.id)} AND r.enabled=true AND u.disconnected_at IS NULL`;
    for (const row of repos) {
      const repo = row.descriptor as ConnectedRepository;
      const available = await accessibleRepositories(await userToken(row.user_id));
      if (!available.some(candidate=>candidate.id===repo.id && candidate.installationID===repo.installationID)) {
        await sql`UPDATE repositories SET enabled=false WHERE user_id=${row.user_id} AND id=${repo.id}`;
        continue;
      }
      if (delivery.event==='push') {
        const token = await installationToken(repo);
        for (const commit of payload.commits ?? []) {
          const evidence = await collectCommit(repo,token,commit.id,row.github_id,row.include_patches);
          if (!evidence) continue;
          await sql`INSERT INTO evidence(user_id,id,repository_id,occurred_at,payload)
            SELECT ${row.user_id},${evidence.id},${repo.id},${evidence.occurredAt},${JSON.stringify(evidence)}::jsonb
            WHERE EXISTS(SELECT 1 FROM users WHERE id=${row.user_id} AND disconnected_at IS NULL)
            ON CONFLICT(user_id,id) DO UPDATE SET payload=EXCLUDED.payload`;
        }
      }
      await enqueue(row.user_id,{day:localDay(row.time_zone),timeZone:row.time_zone});
    }
    await sql`UPDATE webhook_deliveries SET status='completed',payload='{}',processed_at=now(),lease_token=NULL,lease_until=NULL WHERE id=${delivery.id} AND lease_token=${lease}`;
  } catch(error) {
    await sql`UPDATE webhook_deliveries SET status=CASE WHEN attempts>=5 THEN 'failed' ELSE 'pending' END,lease_token=NULL,lease_until=NULL WHERE id=${delivery.id} AND lease_token=${lease}`;
    if (!(error instanceof PublicError)) console.error('Webhook processing failed');
  }
  return true;
}
