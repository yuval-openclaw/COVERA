import 'server-only';
import { HttpError } from './auth';

/** In-memory sliding window, per process. Enough to stop a stranger burning the AI key. */
const hits = new Map<string, number[]>();

export function limit(key: string, max: number, windowMs: number, message: string) {
  const now = Date.now();
  const recent = (hits.get(key) ?? []).filter((t) => now - t < windowMs);
  if (recent.length >= max) throw new HttpError(429, message);
  recent.push(now);
  hits.set(key, recent);
}

export function clientIp(req: Request) {
  return req.headers.get('cf-connecting-ip') ?? req.headers.get('x-forwarded-for')?.split(',')[0].trim() ?? 'local';
}
