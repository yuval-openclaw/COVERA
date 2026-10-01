// Against the real local Postgres, with synthetic identities only. Skipped
// when no database is configured.
import { randomBytes } from 'node:crypto';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { signInWithProvider } from './link.js';

const url = process.env.DATABASE_URL;
const pool = url ? new pg.Pool({ connectionString: url }) : undefined;
const suite = pool ? describe : describe.skip;
const made: string[] = [];

function address(): string {
  const email = `link-${randomBytes(6).toString('hex')}@test.covera.invalid`;
  made.push(email);
  return email;
}

async function preregister(email: string): Promise<string> {
  const { rows } = await pool!.query<{ id: string }>(
    `INSERT INTO users (email, password_hash) VALUES ($1, 'scrypt$attacker') RETURNING id`, [email]);
  await pool!.query(
    `INSERT INTO sessions (user_id, token_hash, expires_at) VALUES ($1, $2, now() + interval '1 day')`,
    [rows[0]!.id, randomBytes(32).toString('hex')]);
  return rows[0]!.id;
}

async function credentials(id: string) {
  const user = await pool!.query<{ password_hash: string | null }>(`SELECT password_hash FROM users WHERE id = $1`, [id]);
  const sessions = await pool!.query(`SELECT 1 FROM sessions WHERE user_id = $1`, [id]);
  return { password: user.rows[0]!.password_hash, sessions: sessions.rowCount };
}

suite('signInWithProvider (database)', () => {
  afterAll(async () => {
    await pool!.query(`DELETE FROM users WHERE email = ANY($1)`, [made]);
    await pool!.end();
  });

  for (const provider of ['google', 'apple'] as const) {
    it(`${provider}: a pre-registered password and session stop working once the owner signs in`, async () => {
      const email = address();
      const attacker = await preregister(email);
      const result = await signInWithProvider(pool!, provider, `${provider}-${randomBytes(4).toString('hex')}`, email);
      expect(result).toMatchObject({ ok: true, userId: attacker });
      expect(await credentials(attacker)).toEqual({ password: null, sessions: 0 });
    });
  }

  it('a second verified provider for the same address links without signing anyone out', async () => {
    const email = address();
    const first = await signInWithProvider(pool!, 'google', `g-${randomBytes(4).toString('hex')}`, email);
    if (!first.ok) throw new Error('first sign-in failed');
    await pool!.query(`INSERT INTO sessions (user_id, token_hash, expires_at) VALUES ($1, $2, now() + interval '1 day')`,
      [first.userId, randomBytes(32).toString('hex')]);
    const second = await signInWithProvider(pool!, 'apple', `a-${randomBytes(4).toString('hex')}`, email);
    expect(second).toMatchObject({ ok: true, userId: first.userId });
    expect((await credentials(first.userId)).sessions).toBe(1);
  });

  it('refuses a different identity of the same provider for an already-linked address', async () => {
    const email = address();
    await signInWithProvider(pool!, 'google', `g-${randomBytes(4).toString('hex')}`, email);
    expect(await signInWithProvider(pool!, 'google', `g-${randomBytes(4).toString('hex')}`, email))
      .toEqual({ ok: false, reason: 'linked_to_other' });
  });

  it('concurrent sign-ins for one address end with one account, linked once', async () => {
    const email = address();
    const attacker = await preregister(email);
    const sub = `g-${randomBytes(4).toString('hex')}`;
    const results = await Promise.all([1, 2, 3].map(() => signInWithProvider(pool!, 'google', sub, email)));
    for (const r of results) expect(r).toMatchObject({ ok: true, userId: attacker });
    const rows = await pool!.query(`SELECT 1 FROM users WHERE email = $1`, [email]);
    expect(rows.rowCount).toBe(1);
    expect(await credentials(attacker)).toEqual({ password: null, sessions: 0 });
  });
});
