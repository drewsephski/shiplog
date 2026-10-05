import { Pool } from 'pg';
import { neonConfig } from '@neondatabase/serverless';
import { z } from 'zod';

const querySchema = z.object({query:z.string(),params:z.array(z.unknown())});
/** Exercise the production Neon SQL against an isolated real PostgreSQL instance. No SQL mocks. */
export function installPostgresTransport(url: string) {
  const pool = new Pool({connectionString:url,types:{getTypeParser:()=>value=>value}});
  const previous = neonConfig.fetchFunction;
  neonConfig.fetchFunction = async (_url, init) => {
    const body = JSON.parse(String(init?.body));
    const client = await pool.connect();
    const transaction = 'queries' in body;
    try {
      if (transaction) await client.query('BEGIN');
      const queries = transaction ? z.array(querySchema).parse(body.queries) : [querySchema.parse(body)];
      const results = [];
      for (const query of queries) {
        const result = await client.query({text:query.query,values:query.params,rowMode:'array'});
        results.push({fields:result.fields.map(field=>({name:field.name,dataTypeID:field.dataTypeID})),rows:result.rows,rowCount:result.rowCount,
          command:result.command,rowAsArray:true});
      }
      if (transaction) await client.query('COMMIT');
      return Response.json(transaction ? {results} : results[0]);
    } catch(error) {
      if (transaction) await client.query('ROLLBACK');
      throw error;
    } finally { client.release(); }
  };
  return {pool, async close() { neonConfig.fetchFunction=previous;await pool.end(); }};
}
