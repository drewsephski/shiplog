import { after } from 'next/server';
import { verifyWebhook, required, PublicError } from '@/lib/security';
import { receiveWebhook, processWebhook } from '@/lib/webhooks';
import { runJob } from '@/lib/jobs';
import { route } from '@/lib/http';
export const maxDuration = 300;
export function POST(request: Request) { return route(async()=>{
  const body = await request.text();
  if (Buffer.byteLength(body)>1_000_000) throw new PublicError(413,'too_large','Webhook is too large. Reconciliation will recover activity.');
  if (!verifyWebhook(body,request.headers.get('x-hub-signature-256'),required('GITHUB_WEBHOOK_SECRET')))
    throw new PublicError(401,'invalid_signature','Invalid webhook signature.');
  const id = request.headers.get('x-github-delivery') ?? '';
  if (!/^[a-zA-Z0-9-]{16,100}$/.test(id)) throw new PublicError(400,'invalid_delivery','Missing delivery identity.');
  const event = request.headers.get('x-github-event') ?? '';
  await receiveWebhook(id,event,JSON.parse(body));
  after(async()=>{ await processWebhook(); await runJob(); });
  return Response.json({accepted:true});
}); }
