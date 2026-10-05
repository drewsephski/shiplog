import { z } from 'zod';
import { kindSchema } from './domain';
import { db } from './db';
import { PublicError } from './security';
export const editSchema = z.object({
  mutationID:z.uuid(),targetID:z.uuid(),targetType:z.enum(['entry','narrative']),deleted:z.boolean(),
  title:z.string().min(1).max(240).optional(),detail:z.string().max(20000).optional(),kind:kindSchema.optional(),
  occurredAt:z.iso.datetime({offset:true}).optional(),
}).superRefine((edit,context)=>{
  if (edit.deleted) return;
  if (!edit.detail || (edit.targetType==='entry' && (!edit.title || !edit.kind || !edit.occurredAt))) {
    if (edit.detail === '' && edit.targetType === 'entry' && edit.title && edit.kind && edit.occurredAt) return;
    context.addIssue({code:'custom',message:'Missing edit fields'});
  }
});
export async function applyEdits(userID: string, input: z.infer<typeof editSchema>[]) {
  const sql = db();
  const journalIDs = input.filter(edit=>edit.targetType==='narrative').map(edit=>edit.targetID);
  const entryIDs = input.filter(edit=>edit.targetType==='entry').map(edit=>edit.targetID);
  const owned = await sql`SELECT id::text FROM journals WHERE user_id=${userID} AND id=ANY(${journalIDs}::uuid[])
    UNION ALL SELECT e.id::text FROM entries e JOIN journals j ON j.id=e.journal_id WHERE j.user_id=${userID} AND e.id=ANY(${entryIDs}::uuid[])`;
  if (new Set(owned.map(item=>item.id)).size!==new Set(input.map(edit=>edit.targetID)).size)
    throw new PublicError(409,'stale_edit','A draft is no longer available on the server. Your local words are preserved.');
  // Each local outbox mutation is applied once, even if an HTTP response is lost.
  await sql.transaction(input.map(edit=> edit.targetType==='entry'
    ? sql`WITH mutation AS (
        INSERT INTO applied_edits(user_id,id) VALUES(${userID},${edit.mutationID}) ON CONFLICT DO NOTHING RETURNING id
      ) UPDATE entries SET user_edited=true,user_deleted=${edit.deleted},retired=false,
        title=COALESCE(${edit.title ?? null},title),detail=COALESCE(${edit.detail ?? null},detail),
        kind=COALESCE(${edit.kind ?? null},kind),occurred_at=COALESCE(${edit.occurredAt ?? null}::timestamptz,occurred_at)
        WHERE id=${edit.targetID} AND EXISTS(SELECT 1 FROM mutation)
        AND journal_id IN(SELECT id FROM journals WHERE user_id=${userID})`
    : sql`WITH mutation AS (
        INSERT INTO applied_edits(user_id,id) VALUES(${userID},${edit.mutationID}) ON CONFLICT DO NOTHING RETURNING id
      ) UPDATE journals SET narrative_edited=true,narrative_deleted=${edit.deleted},
        narrative=COALESCE(${edit.detail ?? null},narrative) WHERE id=${edit.targetID} AND user_id=${userID}
        AND EXISTS(SELECT 1 FROM mutation)`));
  return input.map(edit=>edit.mutationID);
}
