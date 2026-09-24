import { randomBytes } from 'node:crypto';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { verifyAppleIdentityToken } from '../auth/apple.js';
import { verifyGoogleIdToken } from '../auth/google.js';
import {
  hashPassword,
  hashToken,
  newSessionToken,
  normalizeEmail,
  passwordProblem,
  verifyPassword,
} from '../auth/passwords.js';
import { env } from '../config/env.js';
import { pool } from '../db/pool.js';
import { allow, MINUTE } from '../auth/rate-limit.js';

const SESSION_DAYS = 30;

function httpError(statusCode: number, message: string): Error {
  return Object.assign(new Error(message), { statusCode });
}

function bearerToken(request: FastifyRequest): string | null {
  const header = request.headers.authorization;
  return header?.startsWith('Bearer ') ? header.slice('Bearer '.length).trim() || null : null;
}

/**
 * Refuses to process health information for an account that has not agreed to
 * the terms and consented to that processing. The app asks first; this makes
 * sure no client, old or modified, can skip it. Export and deletion are not
 * guarded: those rights hold regardless.
 */
export async function requireConsent(userId: string): Promise<void> {
  const { rows } = await pool.query<{ ok: boolean }>(
    `SELECT (terms_accepted_at IS NOT NULL AND health_consent_at IS NOT NULL
             AND not_advice_acknowledged_at IS NOT NULL) AS ok
     FROM users WHERE id = $1`,
    [userId],
  );
  if (!rows[0]?.ok) {
    throw httpError(403, 'Please accept the terms and consent in the app before adding or asking about policies.');
  }
}

/**
 * The signed-in user for this request, from its bearer session token.
 * Every route that touches a user's data starts here.
 */
export async function requireUserId(request: FastifyRequest): Promise<string> {
  const token = bearerToken(request);
  if (!token) throw httpError(401, 'Sign in to continue.');

  const tokenHash = hashToken(token);
  const { rows } = await pool.query<{ user_id: string; renew: boolean }>(
    `SELECT s.user_id, s.expires_at < now() + make_interval(days => $2) AS renew
     FROM sessions s
     JOIN users u ON u.id = s.user_id
     WHERE s.token_hash = $1 AND s.expires_at > now() AND u.deleted_at IS NULL`,
    [tokenHash, SESSION_DAYS / 2],
  );
  const session = rows[0];
  if (!session) throw httpError(401, 'Your session has ended. Sign in again.');

  // Sessions slide while they are used, so an active user is never signed out
  // and a guest (whose token is the only key) never loses an account in use.
  // Only a session left untouched for the full lifetime expires.
  if (session.renew) {
    await pool.query(
      `UPDATE sessions SET expires_at = now() + make_interval(days => $2) WHERE token_hash = $1`,
      [tokenHash, SESSION_DAYS],
    );
  }
  return session.user_id;
}

async function startSession(userId: string, email: string) {
  const token = newSessionToken();
  await pool.query(
    `INSERT INTO sessions (user_id, token_hash, expires_at)
     VALUES ($1, $2, now() + make_interval(days => $3))`,
    [userId, hashToken(token), SESSION_DAYS],
  );
  return { token, user: { id: userId, email } };
}

const credentialsSchema = z.object({
  email: z.string().trim().email().max(254),
  password: z.string().min(1).max(200),
});

// Checked against when an email has no password, so a wrong email and a wrong
// password take the same time and cannot be told apart.
const DECOY_HASH = await hashPassword(randomBytes(24).toString('base64'));

export async function authRoutes(app: FastifyInstance): Promise<void> {
  app.post('/auth/register', async (request, reply) => {
    const parsed = credentialsSchema.safeParse(request.body);
    if (!parsed.success) return reply.status(400).send({ error: 'Enter a valid email address and a password.' });
    if (!(await allow(`register:${request.ip}`, 10, 15 * MINUTE))) {
      return reply.status(429).send({ error: 'Too many attempts. Try again in a few minutes.' });
    }

    const problem = passwordProblem(parsed.data.password);
    if (problem) return reply.status(400).send({ error: problem });

    const email = normalizeEmail(parsed.data.email);
    const { rows } = await pool.query<{ id: string }>(
      `INSERT INTO users (email, password_hash) VALUES ($1, $2)
       ON CONFLICT (email) DO NOTHING
       RETURNING id`,
      [email, await hashPassword(parsed.data.password)],
    );
    const user = rows[0];
    if (!user) {
      return reply.status(409).send({ error: 'An account with this email already exists. Sign in instead.' });
    }
    return reply.status(201).send(await startSession(user.id, email));
  });

  app.post('/auth/login', async (request, reply) => {
    const parsed = credentialsSchema.safeParse(request.body);
    if (!parsed.success) return reply.status(400).send({ error: 'Enter your email address and password.' });

    const email = normalizeEmail(parsed.data.email);
    // Two buckets. Per (address, email) stops a single account being ground
    // through; per address alone stops the same address spraying one password
    // across a list of emails, which the per-email bucket never sees because
    // each email is only tried once. Both must pass.
    const ipOk = await allow(`login-ip:${request.ip}`, 50, 15 * MINUTE);
    const pairOk = await allow(`login:${request.ip}:${email}`, 10, 15 * MINUTE);
    if (!ipOk || !pairOk) {
      return reply.status(429).send({ error: 'Too many attempts. Try again in a few minutes.' });
    }

    const { rows } = await pool.query<{ id: string; password_hash: string | null }>(
      `SELECT id, password_hash FROM users WHERE email = $1 AND deleted_at IS NULL`,
      [email],
    );
    const user = rows[0];
    const valid = await verifyPassword(parsed.data.password, user?.password_hash ?? DECOY_HASH);
    if (!user?.password_hash || !valid) {
      // One message for every failure: which emails have accounts is private.
      return reply.status(401).send({ error: 'Email or password is incorrect.' });
    }
    return reply.send(await startSession(user.id, email));
  });

  app.post('/auth/google', async (request, reply) => {
    if (!env.GOOGLE_IOS_CLIENT_ID) {
      return reply.status(503).send({ error: 'Google sign-in is not set up on this server yet.' });
    }
    const parsed = z.object({ idToken: z.string().min(20).max(4096) }).safeParse(request.body);
    if (!parsed.success) return reply.status(400).send({ error: 'Google sign-in did not return a token.' });
    if (!(await allow(`google:${request.ip}`, 30, 15 * MINUTE))) {
      return reply.status(429).send({ error: 'Too many attempts. Try again in a few minutes.' });
    }

    let identity;
    try {
      identity = await verifyGoogleIdToken(parsed.data.idToken, env.GOOGLE_IOS_CLIENT_ID);
    } catch (error) {
      request.log.warn({ err: error }, 'google sign-in rejected');
      return reply.status(401).send({ error: 'Google sign-in could not be verified. Try again.' });
    }

    // The Google account id is the stable identity; the address can change.
    const known = await pool.query<{ id: string; email: string }>(
      `SELECT id, email FROM users WHERE google_sub = $1 AND deleted_at IS NULL`,
      [identity.sub],
    );
    if (known.rows[0]) return reply.send(await startSession(known.rows[0].id, known.rows[0].email));

    // New to Covera, or an existing email account signing in with Google for
    // the first time. Google has verified the address, so they are linked.
    const { rows } = await pool.query<{ id: string }>(
      `INSERT INTO users (email, google_sub) VALUES ($1, $2)
       ON CONFLICT (email) DO UPDATE SET google_sub = EXCLUDED.google_sub
         WHERE users.google_sub IS NULL AND users.deleted_at IS NULL
       RETURNING id`,
      [identity.email, identity.sub],
    );
    const user = rows[0];
    if (!user) {
      return reply.status(409).send({ error: 'This email is already linked to a different Google account.' });
    }
    return reply.send(await startSession(user.id, identity.email));
  });

  // Required by App Review (Guideline 4.8) wherever Google sign-in is offered,
  // and the better of the two for this app: Apple's private relay means someone
  // can keep a policy library without handing over a real address.
  app.post('/auth/apple', async (request, reply) => {
    const parsed = z
      .object({ identityToken: z.string().min(20).max(4096), nonce: z.string().min(16).max(256) })
      .safeParse(request.body);
    if (!parsed.success) return reply.status(400).send({ error: 'Apple sign-in did not return a token.' });
    if (!(await allow(`apple:${request.ip}`, 30, 15 * MINUTE))) {
      return reply.status(429).send({ error: 'Too many attempts. Try again in a few minutes.' });
    }

    let identity;
    try {
      identity = await verifyAppleIdentityToken(
        parsed.data.identityToken,
        env.APPLE_BUNDLE_ID,
        parsed.data.nonce,
      );
    } catch (error) {
      request.log.warn({ err: error }, 'apple sign-in rejected');
      return reply.status(401).send({ error: 'Apple sign-in could not be verified. Try again.' });
    }

    const known = await pool.query<{ id: string; email: string }>(
      `SELECT id, email FROM users WHERE apple_sub = $1 AND deleted_at IS NULL`,
      [identity.sub],
    );
    if (known.rows[0]) return reply.send(await startSession(known.rows[0].id, known.rows[0].email));

    // Apple can withhold the address entirely. Rather than refuse the sign-in,
    // the account gets an address nobody can send to — the subject is what
    // signs them back in, and Account still offers export and deletion.
    const email = identity.email ?? `apple-${randomBytes(9).toString('hex')}@appleid.covera.invalid`;

    // New to Covera, or an existing account signing in with Apple for the first
    // time. Apple verified the address, so the two are the same person.
    const { rows } = await pool.query<{ id: string }>(
      `INSERT INTO users (email, apple_sub) VALUES ($1, $2)
       ON CONFLICT (email) DO UPDATE SET apple_sub = EXCLUDED.apple_sub
         WHERE users.apple_sub IS NULL AND users.deleted_at IS NULL
       RETURNING id`,
      [email, identity.sub],
    );
    const user = rows[0];
    if (!user) {
      return reply.status(409).send({ error: 'This email is already linked to a different Apple account.' });
    }
    return reply.send(await startSession(user.id, email));
  });

  app.post('/auth/logout', async (request, reply) => {
    const token = bearerToken(request);
    if (token) await pool.query(`DELETE FROM sessions WHERE token_hash = $1`, [hashToken(token)]);
    return reply.status(204).send();
  });

  app.get('/auth/me', async (request) => {
    const userId = await requireUserId(request);
    const { rows } = await pool.query<{
      email: string;
      has_password: boolean;
      has_google: boolean;
      has_apple: boolean;
      consent_version: string | null;
    }>(
      // consent_version is set only when all three agreements were recorded
      // for the same version; the app shows the agreement screen otherwise.
      `SELECT email, password_hash IS NOT NULL AS has_password, google_sub IS NOT NULL AS has_google,
              apple_sub IS NOT NULL AS has_apple,
              CASE WHEN terms_version = health_consent_version AND not_advice_acknowledged_at IS NOT NULL
                   THEN terms_version END AS consent_version
       FROM users WHERE id = $1`,
      [userId],
    );
    return { user: rows[0] };
  });
}
