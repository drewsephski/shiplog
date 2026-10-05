import { neon } from '@neondatabase/serverless';
import { required } from './security';
// Lazy configuration: a build must not require or embed production secrets.
export function db() { return neon(required('DATABASE_URL')); }
