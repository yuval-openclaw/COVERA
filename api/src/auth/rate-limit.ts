import { createHash } from 'node:crypto';
import { pool } from '../db/pool.js';

export const MINUTE = 60_000;
export const HOUR = 60 * MINUTE;
export const DAY = 24 * HOUR;

/**
 * Counts one attempt against `key` and says whether it is within `limit` for
 * the current window. Atomic in one statement, so concurrent requests cannot
 * both slip under the limit, and stored in Postgres so a restart does not
 * hand an attacker a fresh allowance.
 *
 * Two jobs: slowing password guessing, and capping the routes that spend money
 * on the AI provider, so one account or one address cannot run up the bill.
 */
export async function allow(key: string, limit: number, windowMs: number): Promise<boolean> {
  const { rows } = await pool.query<{ count: number }>(
    `INSERT INTO rate_limits (key_hash, count, reset_at)
     VALUES ($1, 1, now() + make_interval(secs => $2))
     ON CONFLICT (key_hash) DO UPDATE SET
       count = CASE WHEN rate_limits.reset_at < now() THEN 1 ELSE rate_limits.count + 1 END,
       reset_at = CASE WHEN rate_limits.reset_at < now()
                       THEN now() + make_interval(secs => $2)
                       ELSE rate_limits.reset_at END
     RETURNING count`,
    [hashKey(key), windowMs / 1000],
  );

  // Expired rows are useless; clear them now and then rather than on a timer.
  if (Math.random() < 0.01) {
    await pool.query(`DELETE FROM rate_limits WHERE reset_at < now() - interval '1 day'`);
  }

  return rows[0]!.count <= limit;
}

function hashKey(key: string): string {
  return createHash('sha256').update(key).digest('hex');
}
