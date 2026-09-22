import { describe, expect, it } from 'vitest';
import {
  hashPassword,
  hashToken,
  newSessionToken,
  normalizeEmail,
  passwordProblem,
  verifyPassword,
} from './passwords.js';

describe('passwords', () => {
  it('verifies the right password and rejects a wrong one', async () => {
    const stored = await hashPassword('correct horse battery');
    expect(await verifyPassword('correct horse battery', stored)).toBe(true);
    expect(await verifyPassword('correct horse battery!', stored)).toBe(false);
  });

  it('never stores the password, and salts every hash', async () => {
    const a = await hashPassword('same password here');
    const b = await hashPassword('same password here');
    expect(a).not.toContain('same password here');
    expect(a).not.toEqual(b);
  });

  it('treats a malformed stored hash as a failed login, not a crash', async () => {
    expect(await verifyPassword('anything at all', 'not-a-hash')).toBe(false);
    expect(await verifyPassword('anything at all', '')).toBe(false);
  });

  it('requires at least 10 characters', () => {
    expect(passwordProblem('short')).not.toBeNull();
    expect(passwordProblem('long enough pw')).toBeNull();
  });
});

describe('sessions and emails', () => {
  it('stores tokens only as a stable hash', () => {
    const token = newSessionToken();
    expect(token.length).toBeGreaterThanOrEqual(43);
    expect(hashToken(token)).toEqual(hashToken(token));
    expect(hashToken(token)).not.toContain(token);
    expect(newSessionToken()).not.toEqual(token);
  });

  it('matches emails regardless of case and stray spaces', () => {
    expect(normalizeEmail('  Dana@Example.COM ')).toBe('dana@example.com');
  });
});
