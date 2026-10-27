// TEMPORARY GUEST MODE. Real Postgres, synthetic accounts only; skipped when
// no database is configured.
import { randomBytes } from 'node:crypto';
import { afterAll, describe, expect, it } from 'vitest';

const suite = process.env.DATABASE_URL ? describe : describe.skip;

suite('deleteUnreachableGuests (database)', async () => {
  const { pool } = await import('../db/pool.js');
  const { deleteUnreachableGuests } = await import('./delete.js');
  const made: string[] = [];

  async function user(email: string, ageDays: number, liveSession: boolean): Promise<string> {
    made.push(email);
    const { rows } = await pool.query<{ id: string }>(
      `INSERT INTO users (email, created_at) VALUES ($1, now() - make_interval(days => $2)) RETURNING id`,
      [email, ageDays],
    );
    if (liveSession) {
      await pool.query(`INSERT INTO sessions (user_id, token_hash, expires_at) VALUES ($1, $2, now() + interval '1 day')`,
        [rows[0]!.id, randomBytes(32).toString('hex')]);
    }
    return rows[0]!.id;
  }
  const exists = async (id: string) => ((await pool.query(`SELECT 1 FROM users WHERE id = $1`, [id])).rowCount ?? 0) > 0;
  const tag = () => randomBytes(6).toString('hex');

  afterAll(async () => {
    await pool.query(`DELETE FROM users WHERE email = ANY($1)`, [made]);
  });

  it('deletes a guest nobody can reach, and nothing else', async () => {
    const stranded = await user(`guest-${tag()}@guest.clausa.invalid`, 40, false);
    const active = await user(`guest-${tag()}@guest.clausa.invalid`, 40, true);
    const fresh = await user(`guest-${tag()}@guest.clausa.invalid`, 0, false);
    const regular = await user(`someone-${tag()}@test.clausa.invalid`, 40, false);

    await deleteUnreachableGuests(() => undefined);

    expect(await exists(stranded)).toBe(false);
    expect(await exists(active)).toBe(true);
    expect(await exists(fresh)).toBe(true);
    expect(await exists(regular)).toBe(true);
  });
});
