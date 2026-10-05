import { db } from './db';
import { hash } from './domain';
import { PublicError } from './security';
export interface AgentUser {id:string;githubID:string;login:string;timeZone:string;finalizeMinute:number;includePatches:boolean}
export async function authenticate(request: Request): Promise<AgentUser> {
  const authorization = request.headers.get('authorization');
  if (!authorization?.match(/^Bearer [A-Za-z0-9_-]{43}$/)) throw new PublicError(401,'unauthorized','Reconnect GitHub to continue.');
  const sql = db();
  const [user] = await sql`SELECT u.* FROM sessions s JOIN users u ON u.id=s.user_id
    WHERE s.token_hash=${hash(authorization.slice(7))} AND s.expires_at>now() AND u.disconnected_at IS NULL`;
  if (!user) throw new PublicError(401,'unauthorized','Reconnect GitHub to continue.');
  return {id:user.id,githubID:user.github_id,login:user.login,timeZone:user.time_zone,
    finalizeMinute:user.finalize_minute,includePatches:user.include_patches};
}
export async function rateLimit(key: string, limit: number, seconds: number) {
  const sql = db();
  const [bucket] = await sql`INSERT INTO request_buckets(key,count,reset_at) VALUES(${key},1,now()+${seconds}*interval '1 second')
    ON CONFLICT(key) DO UPDATE SET count=CASE WHEN request_buckets.reset_at<now() THEN 1 ELSE request_buckets.count+1 END,
    reset_at=CASE WHEN request_buckets.reset_at<now() THEN now()+${seconds}*interval '1 second' ELSE request_buckets.reset_at END
    RETURNING count`;
  if (bucket.count>limit) throw new PublicError(429,'rate_limited','Please wait a moment before trying again.');
}
