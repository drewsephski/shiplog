import { createHmac } from 'node:crypto';
import { route } from './http';
import { cookies } from 'next/headers';
import { z } from 'zod';
import { db } from './db';
import { hash } from './domain';
import { decrypt, PublicError, publicURL, required } from './security';
import { accessibleRepositories } from './github';

// Build 2 pins its initial sign-in URL to this existing production alias.
// Retain that exact origin for the first hop; the browser then establishes its
// secure flow cookie on the canonical origin. Never trust arbitrary Host values.
export function connectionStartURL(request: Request, state: string) {
  const origin = new URL(request.url).origin;
  const initialOrigin = origin === 'https://shiplog-agent.vercel.app' ? origin : publicURL();
  return `${initialOrigin}/connect/begin?state=${encodeURIComponent(state)}`;
}
export const FLOW_COOKIE = '__Host-shiplog-connect';
export async function flow() {
  const state = (await cookies()).get(FLOW_COOKIE)?.value;
  if (!state) throw new PublicError(400,'connection_expired','Restart Connect GitHub in Shiplog.');
  const sql = db();
  const [attempt] = await sql`SELECT * FROM connect_attempts WHERE state_hash=${hash(state)} AND expires_at>now() AND consumed_at IS NULL`;
  if (!attempt) throw new PublicError(400,'connection_expired','Restart Connect GitHub in Shiplog.');
  return {state,attempt};
}
export function escapeHTML(value: string) {
  return value.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;').replaceAll("'",'&#39;');
}
export function html(title: string, body: string, status = 200) {
  return new Response(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escapeHTML(title)} · Shiplog</title><style>
  :root{color-scheme:light dark;font-family:system-ui;background:light-dark(#faf9f7,#111);color:light-dark(#161616,#eee)}
  body{max-width:520px;margin:7vh auto;padding:24px}h1{font-size:36px;letter-spacing:-1px}p{line-height:1.6;color:light-dark(#555,#aaa)}
  label{display:block;padding:16px 0;border-bottom:1px solid #8884}small{color:light-dark(#666,#aaa)}input{margin-right:12px}
  button,.action{font:inherit;display:inline-block;margin-top:24px;padding:14px 20px;border:0;border-radius:12px;background:light-dark(#171717,#eee);color:light-dark(#fff,#111);text-decoration:none}a{color:inherit}
  </style></head><body><b>Shiplog</b><h1>${escapeHTML(title)}</h1>${body}</body></html>`,{
    status, headers:{'Content-Type':'text/html; charset=utf-8','Cache-Control':'no-store',
      'Content-Security-Policy':"default-src 'none'; style-src 'unsafe-inline'; form-action 'self' shiplog:; base-uri 'none'; frame-ancestors 'none'"},
  });
}
/** Keep connection failures readable in the authentication browser. API errors remain JSON. */
export async function browserRoute(action: () => Promise<Response>) {
  const response = await route(action);
  if (response.ok || !response.headers.get('Content-Type')?.includes('application/json')) return response;
  const error = z.object({error:z.string()}).parse(await response.json());
  const page = html('Let’s reconnect.', `<p>${escapeHTML(error.error)}</p><p>Close this sign-in window, then tap Connect GitHub again in Shiplog.</p>`,response.status);
  const retryAfter = response.headers.get('Retry-After');
  if (retryAfter) page.headers.set('Retry-After',retryAfter);
  return page;
}
/** Stable within a flow so reloading or navigating back cannot invalidate a visible form. */
export function connectionCSRF(state: string) {
  return createHmac('sha256',required('TOKEN_ENCRYPTION_KEY')).update(`shiplog-repository-consent:${state}`).digest('base64url');
}
export async function repositoryPage() {
  const {state,attempt} = await flow();
  if (attempt.selection_claimed_at) throw new PublicError(400,'already_used','Your repository selection was saved, but this connection has already been submitted.');
  if (!attempt.access_token) throw new PublicError(401,'github_required','Authorize GitHub first.');
  const repositories = await accessibleRepositories(decrypt(attempt.access_token));
  const csrf = connectionCSRF(state);
  const sql = db();
  await sql`UPDATE connect_attempts SET csrf_hash=${hash(csrf)} WHERE state_hash=${hash(state)} AND consumed_at IS NULL`;
  const install = `https://github.com/apps/${encodeURIComponent(required('GITHUB_APP_SLUG'))}/installations/new?state=${encodeURIComponent(state)}`;
  return html('Keep the story of your work.', `<p>Connected as <strong>${escapeHTML(attempt.login)}</strong>. Choose up to 10 repositories. Shiplog imports only activity attributable to your GitHub identity.</p>
    <form method="post" action="/connect/repositories"><input type="hidden" name="csrf" value="${csrf}">
    ${repositories.map(repo=>`<label><input type="checkbox" name="repository" value="${escapeHTML(repo.id)}">${escapeHTML(repo.fullName)} <small>${repo.isPrivate ? 'Private' : 'Public'}</small></label>`).join('')}
    <p><a href="${install}">Install Shiplog or change GitHub repository access</a></p>
    <p>Selected repository metadata, README, manifests, architecture excerpts, commit messages, PR/issue text, changed filenames, and diff statistics are stored by Shiplog and sent to the configured AI provider to write draft entries. Private repositories are included only when you select them. Repository text may contain sensitive information; choose accordingly.</p>
    <label><input type="checkbox" name="patches" value="yes">Also include bounded code patches (optional)</label>
    <label><input type="checkbox" name="consent" value="yes" required>I agree to this transfer of selected repository context and activity.</label>
    <button type="submit">Analyze today in Shiplog</button></form><p><small>You can edit drafts, disconnect GitHub, or delete server data in Settings. No analytics or advertising.</small></p>`);
}
export const connectionInput = z.object({challenge:z.string().regex(/^[A-Za-z0-9_-]{43}$/),timeZone:z.string().max(100)});
export function authorizeURL(state: string) {
  const url = new URL('https://github.com/login/oauth/authorize');
  url.search = new URLSearchParams({client_id:required('GITHUB_CLIENT_ID'),redirect_uri:`${publicURL()}/connect/callback`,state}).toString();
  return url;
}
