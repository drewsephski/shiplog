import { db } from '@/lib/db';
import { hash, dayRequest } from '@/lib/domain';
import { connectionInput, connectionStartURL } from '@/lib/connect';
import { rateLimit } from '@/lib/auth';
import { randomToken, required } from '@/lib/security';
import { jsonBody, route } from '@/lib/http';
export const runtime = 'nodejs';
export function POST(request: Request) { return route(async()=>{
  for (const name of ['GITHUB_APP_ID','GITHUB_APP_SLUG','GITHUB_CLIENT_ID','GITHUB_CLIENT_SECRET','GITHUB_PRIVATE_KEY',
    'GITHUB_WEBHOOK_SECRET','TOKEN_ENCRYPTION_KEY','OPENROUTER_API_KEY','OPENROUTER_MODEL','CRON_SECRET']) required(name);
  const input = connectionInput.parse(await jsonBody(request));
  dayRequest.parse({day:'2026-01-01',timeZone:input.timeZone});
  await rateLimit(`connect:${hash(request.headers.get('x-forwarded-for') ?? 'unknown')}`,20,3600);
  const state = randomToken(); const sql = db();
  await sql`INSERT INTO connect_attempts(state_hash,challenge,time_zone) VALUES(${hash(state)},${input.challenge},${input.timeZone})`;
  return Response.json({url:connectionStartURL(request,state)});
}); }
