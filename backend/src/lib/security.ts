import { createCipheriv, createDecipheriv, randomBytes, timingSafeEqual, createHmac } from 'node:crypto';
import { hash } from './domain';

export function required(name: string): string {
  const value = process.env[name];
  if (!value) throw new PublicError(503, 'not_configured', 'The Shiplog agent is not configured yet.');
  return value;
}
export class PublicError extends Error {
  constructor(public status: number, public code: string, message: string, public retryAfterSeconds = 300) { super(message); }
}
export const randomToken = () => randomBytes(32).toString('base64url');
export function equal(a: string, b: string) {
  const left = Buffer.from(a); const right = Buffer.from(b);
  return left.length === right.length && timingSafeEqual(left, right);
}
export function verifyWebhook(body: string, signature: string | null, secret: string) {
  if (!signature?.startsWith('sha256=')) return false;
  return equal(signature, `sha256=${createHmac('sha256',secret).update(body).digest('hex')}`);
}
export function challenge(verifier: string) { return Buffer.from(hash(verifier), 'hex').toString('base64url'); }
function encryptionKey() {
  const key = Buffer.from(required('TOKEN_ENCRYPTION_KEY'), 'base64');
  if (key.length !== 32) throw new PublicError(503, 'not_configured', 'Token protection is not configured.');
  return key;
}
export function encrypt(value: string) {
  const nonce = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', encryptionKey(), nonce);
  const encrypted = Buffer.concat([cipher.update(value,'utf8'),cipher.final()]);
  return Buffer.concat([nonce,cipher.getAuthTag(),encrypted]).toString('base64');
}
export function decrypt(value: string) {
  const data = Buffer.from(value,'base64');
  const decipher = createDecipheriv('aes-256-gcm', encryptionKey(), data.subarray(0,12));
  decipher.setAuthTag(data.subarray(12,28));
  return Buffer.concat([decipher.update(data.subarray(28)),decipher.final()]).toString('utf8');
}
export function publicURL() {
  const url = new URL(required('SHIPLOG_PUBLIC_URL'));
  if (url.protocol !== 'https:') throw new PublicError(503,'not_configured','A secure agent URL is required.');
  return url.origin;
}
export function assertSameOrigin(request: Request) {
  if (request.headers.get('origin') !== publicURL()) throw new PublicError(403,'invalid_origin','Please restart the connection.');
}
