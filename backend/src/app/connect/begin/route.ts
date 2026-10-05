import { cookies } from 'next/headers';
import { db } from '@/lib/db';
import { hash } from '@/lib/domain';
import { authorizeURL, FLOW_COOKIE } from '@/lib/connect';
import { PublicError } from '@/lib/security';
import { route } from '@/lib/http';
export function GET(request: Request) { return route(async()=>{
  const state = new URL(request.url).searchParams.get('state') ?? '';
  if (!/^[A-Za-z0-9_-]{43}$/.test(state)) throw new PublicError(400,'invalid_state','Restart Connect GitHub.');
  const sql = db();
  const [attempt] = await sql`SELECT state_hash FROM connect_attempts WHERE state_hash=${hash(state)} AND expires_at>now() AND consumed_at IS NULL`;
  if (!attempt) throw new PublicError(400,'invalid_state','Restart Connect GitHub.');
  (await cookies()).set(FLOW_COOKIE,state,{secure:true,httpOnly:true,sameSite:'lax',path:'/',maxAge:900});
  return Response.redirect(authorizeURL(state),303);
}); }
