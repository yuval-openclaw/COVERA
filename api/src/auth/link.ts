import type { Pool } from 'pg';

export type Provider = 'google' | 'apple';

export type LinkResult =
  | { ok: true; userId: string; email: string }
  | { ok: false; reason: 'linked_to_other' };

const COLUMN: Record<Provider, 'google_sub' | 'apple_sub'> = { google: 'google_sub', apple: 'apple_sub' };

/**
 * Signs a verified Google or Apple identity in, linking it to the account that
 * holds its address when there is one.
 *
 * Covera does not verify email addresses at registration, so a password on an
 * account proves nothing about who owns its address. Linking a provider to it
 * as-is let anyone register a victim's address first, wait for the victim to
 * sign in with Google or Apple and upload policies, and then read them with
 * the original password or session. So when a provider proves the address:
 *
 *   - an account with a password loses the password and every session — they
 *     were never shown to belong to the address's owner, who signs in with the
 *     provider from now on;
 *   - an account whose only credentials are another verified provider keeps
 *     its sessions: both providers proved the same address.
 *
 * Runs in one transaction with the row locked, so two sign-ins for the same
 * address cannot both link, and a session minted mid-link cannot survive it.
 */
export async function signInWithProvider(
  pool: Pool,
  provider: Provider,
  sub: string,
  email: string,
): Promise<LinkResult> {
  const column = COLUMN[provider];
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const known = await client.query<{ id: string; email: string }>(
      `SELECT id, email FROM users WHERE ${column} = $1 AND deleted_at IS NULL`,
      [sub],
    );
    if (known.rows[0]) {
      await client.query('COMMIT');
      return { ok: true, userId: known.rows[0].id, email: known.rows[0].email };
    }

    const inserted = await client.query<{ id: string }>(
      `INSERT INTO users (email, ${column}) VALUES ($1, $2) ON CONFLICT (email) DO NOTHING RETURNING id`,
      [email, sub],
    );
    if (inserted.rows[0]) {
      await client.query('COMMIT');
      return { ok: true, userId: inserted.rows[0].id, email };
    }

    const existing = await client.query<{ id: string; has_password: boolean; current: string | null }>(
      `SELECT id, password_hash IS NOT NULL AS has_password, ${column} AS current
         FROM users WHERE email = $1 AND deleted_at IS NULL FOR UPDATE`,
      [email],
    );
    const row = existing.rows[0];
    if (!row || (row.current !== null && row.current !== sub)) {
      await client.query('ROLLBACK');
      return { ok: false, reason: 'linked_to_other' };
    }

    if (row.has_password) {
      await client.query(`UPDATE users SET password_hash = NULL WHERE id = $1`, [row.id]);
      await client.query(`DELETE FROM sessions WHERE user_id = $1`, [row.id]);
    }
    await client.query(`UPDATE users SET ${column} = $2 WHERE id = $1`, [row.id, sub]);
    await client.query('COMMIT');
    return { ok: true, userId: row.id, email };
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    throw error;
  } finally {
    client.release();
  }
}
