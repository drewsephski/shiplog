import { readFile } from 'node:fs/promises';
import { neon } from '@neondatabase/serverless';
const url = process.env.DATABASE_URL;
if (!url) throw new Error('Set DATABASE_URL to the intended development or production database.');
const sql = neon(url);
const migration = await readFile(new URL('../migrations/001_agent.sql', import.meta.url),'utf8');
await sql.transaction(migration.split(';').filter(statement => statement.trim()).map(statement => sql.query(statement)));
console.log('Shiplog agent schema installed.');
