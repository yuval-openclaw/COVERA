/**
 * Verifies an identity token from the iOS app's "Sign in with Apple" flow.
 *
 * Unlike Google, Apple publishes no endpoint that will check a token for you:
 * the only way is to verify the JWT's RS256 signature against the public keys
 * at appleid.apple.com/auth/keys. Node's crypto reads a JWK directly, so this
 * needs no JWT library — and a library here would be one more dependency with
 * access to the thing that decides who someone is.
 *
 * The replay defence is the nonce. The app generates a random string, sends
 * Apple its SHA-256, and sends us the original; a token lifted from somewhere
 * else will not carry the hash of a nonce we were handed in the same request.
 */
import { createHash, createPublicKey, type JsonWebKey, verify as verifySignature } from 'node:crypto';

export interface AppleIdentity {
  sub: string;
  /** Absent when Apple sends no address — see `routes/auth.ts`. */
  email?: string;
}

interface AppleKey {
  kid: string;
  kty: string;
  alg: string;
  n: string;
  e: string;
  use?: string;
}

interface AppleClaims {
  iss?: string;
  aud?: string;
  sub?: string;
  exp?: number;
  iat?: number;
  nonce?: string;
  email?: string;
  email_verified?: string | boolean;
}

const KEYS_URL = 'https://appleid.apple.com/auth/keys';
const ISSUER = 'https://appleid.apple.com';
/** Apple rotates these rarely; a short cache still spares a round trip per sign-in. */
const KEY_CACHE_MS = 60 * 60 * 1000;

let cache: { keys: AppleKey[]; fetchedAt: number } | undefined;

async function appleKeys(force = false): Promise<AppleKey[]> {
  if (!force && cache && Date.now() - cache.fetchedAt < KEY_CACHE_MS) return cache.keys;
  const response = await fetch(KEYS_URL);
  if (!response.ok) throw new Error('Could not fetch Apple’s public keys');
  const body = (await response.json()) as { keys?: AppleKey[] };
  if (!body.keys?.length) throw new Error('Apple returned no public keys');
  cache = { keys: body.keys, fetchedAt: Date.now() };
  return body.keys;
}

/** Exposed for tests, which install a key pair of their own. */
export function __setAppleKeysForTest(keys: AppleKey[] | undefined): void {
  cache = keys ? { keys, fetchedAt: Date.now() } : undefined;
}

function decodeSegment(segment: string): unknown {
  return JSON.parse(Buffer.from(segment, 'base64url').toString('utf8'));
}

/**
 * @param identityToken the JWT from ASAuthorizationAppleIDCredential
 * @param audience the app's bundle identifier — a token minted for another app
 *   must not sign in to this one
 * @param rawNonce the nonce the app generated for this sign-in
 */
export async function verifyAppleIdentityToken(
  identityToken: string,
  audience: string,
  rawNonce: string,
): Promise<AppleIdentity> {
  const parts = identityToken.split('.');
  if (parts.length !== 3) throw new Error('Identity token is malformed');
  const [headerPart, payloadPart, signaturePart] = parts as [string, string, string];

  const header = decodeSegment(headerPart) as { kid?: string; alg?: string };
  // Only RS256 is accepted. Trusting the token's own `alg` is how "alg: none"
  // and HMAC-with-the-public-key forgeries get in.
  if (header.alg !== 'RS256') throw new Error('Identity token is not signed with RS256');
  if (!header.kid) throw new Error('Identity token names no key');

  let keys = await appleKeys();
  let key = keys.find((k) => k.kid === header.kid);
  if (!key) {
    // An unknown key id usually means Apple rotated since we last looked.
    keys = await appleKeys(true);
    key = keys.find((k) => k.kid === header.kid);
  }
  if (!key) throw new Error('Identity token was signed with an unknown key');
  if (key.kty !== 'RSA' || (key.alg && key.alg !== 'RS256')) {
    throw new Error('Apple key is not the expected type');
  }

  const publicKey = createPublicKey({ key: key as unknown as JsonWebKey, format: 'jwk' });
  const signed = Buffer.from(`${headerPart}.${payloadPart}`, 'utf8');
  const signature = Buffer.from(signaturePart, 'base64url');
  if (!verifySignature('RSA-SHA256', signed, publicKey, signature)) {
    throw new Error('Identity token signature does not verify');
  }

  const claims = decodeSegment(payloadPart) as AppleClaims;

  if (claims.iss !== ISSUER) throw new Error('Identity token has an unexpected issuer');
  if (claims.aud !== audience) throw new Error('Identity token was issued for a different app');
  if (!claims.exp || claims.exp * 1000 < Date.now()) throw new Error('Identity token has expired');
  if (!claims.sub) throw new Error('Identity token is missing the subject');

  // Apple hashes whatever the app put in the request; the app keeps the
  // original and sends it here, so the two must agree.
  const expectedNonce = createHash('sha256').update(rawNonce).digest('hex');
  if (claims.nonce !== expectedNonce) throw new Error('Identity token nonce does not match this sign-in');

  // Apple includes the address on the first authorisation and usually after,
  // but a user can hide it and Apple can omit it. An unverified address is
  // dropped rather than trusted: email is how accounts are matched, so one
  // nobody has proved could hand over someone else's account.
  const verified = claims.email_verified === true || claims.email_verified === 'true';
  const email = claims.email && verified ? claims.email.trim().toLowerCase() : undefined;

  return email ? { sub: claims.sub, email } : { sub: claims.sub };
}
