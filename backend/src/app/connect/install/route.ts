import { flow, browserRoute } from '@/lib/connect';
import { equal, PublicError, publicURL } from '@/lib/security';
export function GET(request: Request) { return browserRoute(async()=>{
  const {state} = await flow();
  if (!equal(new URL(request.url).searchParams.get('state') ?? '',state)) throw new PublicError(400,'invalid_state','Restart Connect GitHub.');
  // Installation IDs in this redirect are deliberately ignored. Re-query authorized installations.
  return Response.redirect(`${publicURL()}/connect/repositories`,303);
}); }
