import { createHash, randomBytes, scrypt as scryptCallback, timingSafeEqual } from 'node:crypto';

/**
 * Credential primitives. No database or environment imports, so they are
 * tested directly.
 *
 * scrypt rather than a faster hash: every guess an attacker makes against a
 * stolen hash should cost real memory and time. The parameters are stored with
 * each hash so they can be raised later without invalidating old accounts.
 */

const COST = { N: 2 ** 15, r: 8, p: 1 };
const KEY_LENGTH = 64;
// N=2^15, r=8 needs ~33 MB, just over Node's 32 MB default ceiling.
const MAX_MEMORY = 64 * 1024 * 1024;

function scrypt(password: string, salt: Buffer, length: number, cost: typeof COST): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    scryptCallback(password.normalize('NFKC'), salt, length, { ...cost, maxmem: MAX_MEMORY }, (error, key) =>
      error ? reject(error) : resolve(key),
    );
  });
}

export async function hashPassword(password: string): Promise<string> {
  const salt = randomBytes(16);
  const key = await scrypt(password, salt, KEY_LENGTH, COST);
  return ['scrypt', COST.N, COST.r, COST.p, salt.toString('base64'), key.toString('base64')].join('$');
}

export async function verifyPassword(password: string, stored: string): Promise<boolean> {
  const [scheme, n, r, p, salt, key] = stored.split('$');
  if (scheme !== 'scrypt' || !n || !r || !p || !salt || !key) return false;

  const expected = Buffer.from(key, 'base64');
  const actual = await scrypt(password, Buffer.from(salt, 'base64'), expected.length, {
    N: Number(n),
    r: Number(r),
    p: Number(p),
  });
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

/** A problem to show the person, or null when the password is acceptable. */
export function passwordProblem(password: string): string | null {
  if (password.length < 10) return 'Use at least 10 characters.';
  if (password.length > 200) return 'Use at most 200 characters.';
  return null;
}

export function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

/** 256 bits of randomness; the client holds this, the server keeps only its hash. */
export function newSessionToken(): string {
  return randomBytes(32).toString('base64url');
}

export function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}
