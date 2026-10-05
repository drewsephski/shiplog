#!/usr/bin/env node
// Upload only this service's variables via stdin; never print credential values.
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

process.chdir(fileURLToPath(new URL('..', import.meta.url)));
process.loadEnvFile('backend/.env.local');
const names = [
  'DATABASE_URL', 'SHIPLOG_PUBLIC_URL', 'GITHUB_APP_ID', 'GITHUB_APP_SLUG',
  'GITHUB_CLIENT_ID', 'GITHUB_CLIENT_SECRET', 'GITHUB_PRIVATE_KEY',
  'GITHUB_WEBHOOK_SECRET', 'TOKEN_ENCRYPTION_KEY', 'OPENROUTER_API_KEY',
  'OPENROUTER_MODEL', 'CRON_SECRET',
];
const missing = names.filter(name => !process.env[name]);
const partial = process.argv.includes('--partial');
if (missing.length && !partial) {
  console.error(`Missing configuration: ${missing.join(', ')}`);
  process.exit(1);
}
for (const name of names.filter(name => process.env[name])) {
  const result = spawnSync('vercel', [
    'env', 'add', name, 'production', '--sensitive', '--force', '--yes',
    '--scope', 'drews-projects-870e934b', '--project', 'shiplog-agent',
  ], { input: process.env[name], encoding: 'utf8' });
  if (result.status !== 0) {
    console.error(`Upload failed for ${name} (exit ${result.status}). Credential output suppressed.`);
    process.exit(1);
  }
  console.log(`Configured ${name}`);
}
if (partial) console.log(`Still missing: ${missing.join(', ')}`);
