import { ZodError } from 'zod';
import { PublicError } from './security';
export async function route(action: () => Promise<Response>) {
  try { return await action(); } catch (error) {
    if (error instanceof ZodError) return Response.json({code:'invalid_input',error:'Check the submitted values.'},{status:400});
    if (error instanceof PublicError) return Response.json({code:error.code,error:error.message},{status:error.status,
      headers:error.status===429 ? {'Retry-After':String(error.retryAfterSeconds)} : {}});
    // Do not log GitHub payloads, source code, tokens, or provider response bodies.
    console.error('Shiplog request failed', error instanceof Error ? error.name : 'UnknownError');
    return Response.json({code:'service_failure',error:'Shiplog could not finish. Your saved journal is safe. Please retry.'},{status:503});
  }
}
export async function jsonBody(request: Request, limit = 100_000): Promise<unknown> {
  if (Number(request.headers.get('content-length')) > limit) throw new PublicError(413,'too_large','Request is too large.');
  const text = await request.text();
  if (Buffer.byteLength(text) > limit) throw new PublicError(413,'too_large','Request is too large.');
  try { return JSON.parse(text); } catch { throw new PublicError(400,'invalid_json','Invalid request.'); }
}
