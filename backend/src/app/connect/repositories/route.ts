import { db } from '@/lib/db';
import { flow, repositoryPage, browserRoute } from '@/lib/connect';
import { hash } from '@/lib/domain';
import { accessibleRepositories } from '@/lib/github';
import { assertSameOrigin, decrypt, equal, PublicError, randomToken } from '@/lib/security';
export const GET = () => browserRoute(repositoryPage);
export function POST(request: Request) { return browserRoute(async()=>{
  assertSameOrigin(request);
  const {state,attempt} = await flow();
  if (attempt.selection_claimed_at) throw new PublicError(400,'already_used','Your repository selection was saved, but this connection has already been submitted.');
  const form = await request.formData();
  if (!attempt.access_token || !equal(hash(String(form.get('csrf'))),attempt.csrf_hash ?? '') || form.get('consent')!=='yes')
    throw new PublicError(403,'consent_required','Select repositories and confirm the data transfer.');
  const selected = form.getAll('repository').map(String);
  if (!selected.length || selected.length>10 || new Set(selected).size!==selected.length)
    throw new PublicError(400,'choose_repositories','Choose between 1 and 10 repositories.');
  const available = await accessibleRepositories(decrypt(attempt.access_token));
  const repositories = available.filter(repo=>selected.includes(repo.id));
  if (repositories.length!==selected.length) throw new PublicError(403,'repository_access','Repository access changed. Reload and choose again.');
  const code = randomToken(); const sql = db();
  // The atomic claim prevents duplicate submits from racing repository selections.
  const [claim] = await sql`UPDATE connect_attempts SET selection_claimed_at=now() WHERE state_hash=${hash(state)}
    AND selection_claimed_at IS NULL AND expires_at>now() RETURNING state_hash`;
  if (!claim) throw new PublicError(400,'already_used','Restart Connect GitHub.');
  try {
    const results = await sql.transaction([
      sql`INSERT INTO users(github_id,login,time_zone,access_token,refresh_token,token_expires_at,include_patches)
        VALUES(${attempt.github_id},${attempt.login},${attempt.time_zone},${attempt.access_token},${attempt.refresh_token},${attempt.token_expires_at},${form.get('patches')==='yes'})
        ON CONFLICT(github_id) DO UPDATE SET login=EXCLUDED.login,time_zone=EXCLUDED.time_zone,access_token=EXCLUDED.access_token,
        refresh_token=EXCLUDED.refresh_token,token_expires_at=EXCLUDED.token_expires_at,include_patches=EXCLUDED.include_patches,disconnected_at=NULL RETURNING id`,
      sql`UPDATE repositories SET enabled=false WHERE user_id=(SELECT id FROM users WHERE github_id=${attempt.github_id})`,
      ...repositories.map(repo=>sql`INSERT INTO repositories(user_id,id,installation_id,descriptor)
        VALUES((SELECT id FROM users WHERE github_id=${attempt.github_id}),${repo.id},${repo.installationID},${JSON.stringify(repo)}::jsonb)
        ON CONFLICT(user_id,id) DO UPDATE SET installation_id=EXCLUDED.installation_id,descriptor=EXCLUDED.descriptor,enabled=true`),
      sql`UPDATE connect_attempts SET code_hash=${hash(code)},user_id=(SELECT id FROM users WHERE github_id=${attempt.github_id}),
        expires_at=now()+interval '2 minutes',access_token=NULL,refresh_token=NULL WHERE state_hash=${hash(state)}`,
    ]);
    if (!results[0][0]) throw new Error('Missing connected user');
  } catch(error) {
    await sql`UPDATE connect_attempts SET selection_claimed_at=NULL WHERE state_hash=${hash(state)}`;
    throw error;
  }
  return Response.redirect(`shiplog://github-connected?code=${code}`,303);
}); }
