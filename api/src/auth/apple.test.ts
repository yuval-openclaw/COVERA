import { createHash, createSign, generateKeyPairSync, type KeyObject } from 'node:crypto';
import { afterEach, describe, expect, it } from 'vitest';
import { __setAppleKeysForTest, verifyAppleIdentityToken } from './apple.js';

const AUDIENCE = 'com.covera.app';
const RAW_NONCE = 'a-random-string-from-the-app';
const HASHED_NONCE = createHash('sha256').update(RAW_NONCE).digest('hex');

const { publicKey, privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const KID = 'test-key';

function installKey(key: KeyObject = publicKey): void {
  const jwk = key.export({ format: 'jwk' }) as Record<string, string>;
  __setAppleKeysForTest([{ ...jwk, kid: KID, kty: 'RSA', alg: 'RS256', use: 'sig' } as never]);
}

function sign(
  claims: Record<string, unknown>,
  options: { header?: Record<string, unknown>; key?: KeyObject; tamper?: boolean } = {},
): string {
  const header = { alg: 'RS256', kid: KID, ...options.header };
  const body = [header, claims]
    .map((part) => Buffer.from(JSON.stringify(part), 'utf8').toString('base64url'))
    .join('.');
  const signer = createSign('RSA-SHA256').update(body);
  const signature = signer.sign(options.key ?? privateKey).toString('base64url');
  return `${body}.${options.tamper ? signature.slice(0, -4) + 'AAAA' : signature}`;
}

function validClaims(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    iss: 'https://appleid.apple.com',
    aud: AUDIENCE,
    sub: '001234.abcdef.5678',
    exp: Math.floor(Date.now() / 1000) + 600,
    iat: Math.floor(Date.now() / 1000),
    nonce: HASHED_NONCE,
    email: 'Eyal@Example.com',
    email_verified: 'true',
    ...overrides,
  };
}

async function verify(token: string): Promise<{ sub: string; email?: string }> {
  return verifyAppleIdentityToken(token, AUDIENCE, RAW_NONCE);
}

describe('verifyAppleIdentityToken', () => {
  afterEach(() => __setAppleKeysForTest(undefined));

  it('accepts a token Apple really signed and normalises the address', async () => {
    installKey();
    await expect(verify(sign(validClaims()))).resolves.toEqual({
      sub: '001234.abcdef.5678',
      email: 'eyal@example.com',
    });
  });

  it('rejects a token signed by anyone else', async () => {
    installKey();
    const impostor = generateKeyPairSync('rsa', { modulusLength: 2048 });
    await expect(verify(sign(validClaims(), { key: impostor.privateKey }))).rejects.toThrow(
      /signature does not verify/,
    );
  });

  it('rejects a token whose payload was edited after signing', async () => {
    installKey();
    await expect(verify(sign(validClaims(), { tamper: true }))).rejects.toThrow(/signature does not verify/);
  });

  // "alg: none" and HMAC-with-the-public-key are the classic JWT forgeries.
  it('rejects any algorithm other than RS256', async () => {
    installKey();
    await expect(verify(sign(validClaims(), { header: { alg: 'none' } }))).rejects.toThrow(/not signed with RS256/);
    await expect(verify(sign(validClaims(), { header: { alg: 'HS256' } }))).rejects.toThrow(/not signed with RS256/);
  });

  it('rejects a token minted for a different app', async () => {
    installKey();
    await expect(verify(sign(validClaims({ aud: 'com.someone.else' })))).rejects.toThrow(/different app/);
  });

  it('rejects an unexpected issuer', async () => {
    installKey();
    await expect(verify(sign(validClaims({ iss: 'https://appleid.example.com' })))).rejects.toThrow(
      /unexpected issuer/,
    );
  });

  it('rejects an expired token', async () => {
    installKey();
    const exp = Math.floor(Date.now() / 1000) - 1;
    await expect(verify(sign(validClaims({ exp })))).rejects.toThrow(/expired/);
  });

  // Without this, a token captured from another sign-in would be replayable.
  it('rejects a token whose nonce is not the one this sign-in used', async () => {
    installKey();
    const other = createHash('sha256').update('a-different-nonce').digest('hex');
    await expect(verify(sign(validClaims({ nonce: other })))).rejects.toThrow(/nonce does not match/);
    await expect(verify(sign(validClaims({ nonce: undefined })))).rejects.toThrow(/nonce does not match/);
    // The raw nonce is what the app kept; the token carries its hash.
    await expect(verify(sign(validClaims({ nonce: RAW_NONCE })))).rejects.toThrow(/nonce does not match/);
  });

  it('rejects a token signed with a key id Apple does not publish', async () => {
    installKey();
    await expect(verify(sign(validClaims(), { header: { kid: 'some-other-key' } }))).rejects.toThrow(
      /unknown key|public keys/,
    );
  });

  // Apple lets a user hide their address, and omits it in some sign-ins.
  it('returns the subject alone when no address is given', async () => {
    installKey();
    const claims = validClaims({ email: undefined, email_verified: undefined });
    await expect(verify(sign(claims))).resolves.toEqual({ sub: '001234.abcdef.5678' });
  });

  // An address nobody has proved could hand over another person's account.
  it('drops an unverified address rather than matching an account on it', async () => {
    installKey();
    await expect(verify(sign(validClaims({ email_verified: 'false' })))).resolves.toEqual({
      sub: '001234.abcdef.5678',
    });
  });

  it('rejects a malformed token', async () => {
    installKey();
    await expect(verify('not.a.jwt.at.all')).rejects.toThrow(/malformed/);
    await expect(verify('onlyonepart')).rejects.toThrow(/malformed/);
  });
});
