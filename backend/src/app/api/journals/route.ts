import { z } from 'zod';
import { authenticate } from '@/lib/auth';
import { db } from '@/lib/db';
import { readJournal } from '@/lib/journal';
import { route } from '@/lib/http';
const cursorSchema=z.object({from:z.iso.datetime({offset:true}),until:z.iso.datetime({offset:true}),after:z.iso.datetime({offset:true}),id:z.uuid()});
export function GET(request: Request) { return route(async()=>{
  const user=await authenticate(request);const params=new URL(request.url).searchParams;const sql=db();
  const [clock]=await sql`SELECT to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS current_time`;
  const since=params.get('since');
  const initial={from:since ? new Date(Date.parse(z.iso.datetime({offset:true}).parse(since))-300_000).toISOString() : '1970-01-01T00:00:00.000Z',
    until:clock.current_time,after:'1970-01-01T00:00:00.000Z',id:'00000000-0000-0000-0000-000000000000'};
  const cursor=params.get('cursor');
  const position=cursor ? cursorSchema.parse(JSON.parse(Buffer.from(z.string().max(2000).parse(cursor),'base64url').toString())) : initial;
  const rows=await sql`SELECT id,day::text,time_zone,
    to_char(updated_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS changed_at FROM journals WHERE user_id=${user.id} AND generated_at IS NOT NULL
    AND updated_at>=${position.from} AND updated_at<=${position.until}
    AND (updated_at,id)>(${position.after}::timestamptz,${position.id}::uuid) ORDER BY updated_at,id LIMIT 6`;
  const page=rows.slice(0,5);
  const journals=await Promise.all(page.map(row=>readJournal(user.id,{day:row.day,timeZone:row.time_zone})));
  const last=page.at(-1);
  const nextCursor=rows.length>5 && last ? Buffer.from(JSON.stringify({...position,after:last.changed_at,id:last.id})).toString('base64url') : null;
  return Response.json({journals,nextCursor,syncedThrough:position.until});
}); }
