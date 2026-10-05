import { db } from '@/lib/db';
import { hash } from '@/lib/domain';
import { flow } from '@/lib/connect';
import { encrypt, equal, PublicError, publicURL } from '@/lib/security';
import { exchangeGitHub, identity } from '@/lib/github';
import { route } from '@/lib/http';
export function GET(request: Request) { return route(async()=>{
  const params = new URL(request.url).searchParams;
  const {state} = await flow();
  if (!equal(params.get('state') ?? '',state) || !params.get('code')) throw new PublicError(400,'authorization_failed','GitHub authorization was cancelled. Restart in Shiplog.');
  const sql = db();
  const [claimed] = await sql`UPDATE connect_attempts SET oauth_claimed_at=now() WHERE state_hash=${hash(state)} AND oauth_claimed_at IS NULL RETURNING state_hash`;
  if (!claimed) throw new PublicError(400,'already_used','Restart Connect GitHub in Shiplog.');
  const token = await exchangeGitHub(params.get('code')!);
  const user = await identity(token.access_token);
  await sql`UPDATE connect_attempts SET access_token=${encrypt(token.access_token)},
    refresh_token=${token.refresh_token ? encrypt(token.refresh_token) : null},
    token_expires_at=${token.expires_in ? new Date(Date.now()+token.expires_in*1000).toISOString() : null},
    github_id=${String(user.id)},login=${user.login} WHERE state_hash=${hash(state)} AND expires_at>now()`;
  return Response.redirect(`${publicURL()}/connect/repositories`,303);
}); }
