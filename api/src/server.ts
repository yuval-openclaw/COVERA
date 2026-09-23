import cors from '@fastify/cors';
import multipart from '@fastify/multipart';
import Fastify from 'fastify';
import { env } from './config/env.js';
import { pool } from './db/pool.js';
import { accountRoutes } from './routes/account.js';
import { authRoutes } from './routes/auth.js';
import { chatRoutes } from './routes/chat.js';
import { documentRoutes } from './routes/documents.js';
import { guidanceRoutes } from './routes/guidance.js';
import { deleteUnreachableGuests } from './account/delete.js';

const app = Fastify({
  logger: {
    level: env.NODE_ENV === 'production' ? 'info' : 'debug',
    // Policy text and filenames are sensitive; keep them out of logs.
    redact: ['req.headers.authorization', 'req.headers.cookie', '*.text', '*.verbatim_quote'],
  },
  bodyLimit: 25 * 1024 * 1024,
  // A hop count (see env.ts), so req.ip is the address the proxy saw and cannot
  // be forged by a client-supplied X-Forwarded-For.
  // proxy-addr reads a *number* as a hop count (a numeric string would be
  // parsed as a subnet list instead), so the runtime value stays a number;
  // Fastify's option type omits number, hence the cast.
  trustProxy: (env.TRUST_PROXY === 'false'
    ? false
    : Number(env.TRUST_PROXY)) as unknown as boolean,
});

await app.register(cors, { origin: false });
await app.register(multipart, { limits: { fileSize: 25 * 1024 * 1024, files: 1 } });

app.get('/health', async () => {
  await pool.query('SELECT 1');
  return { status: 'ok' };
});

await app.register(authRoutes);
await app.register(documentRoutes);
await app.register(guidanceRoutes);
await app.register(accountRoutes);
await app.register(chatRoutes);

// Expired sign-in sessions and spent rate-limit windows are deleted rather than
// kept: the privacy policy says sessions last until they expire, so they must
// not outlive that. Hourly is often enough; the first sweep runs at start.
const sweep = async (): Promise<void> => {
  try {
    await pool.query(`DELETE FROM sessions WHERE expires_at < now()`);
    await pool.query(`DELETE FROM rate_limits WHERE reset_at < now()`);
    const guests = await deleteUnreachableGuests((message, detail) => app.log.warn(detail, message));
    if (guests > 0) app.log.info({ guests }, 'deleted unreachable guest accounts');
  } catch (error) {
    app.log.warn({ err: error }, 'sweep of expired sessions failed');
  }
};
void sweep();
setInterval(() => void sweep(), 60 * 60_000).unref();

const shutdown = async (): Promise<void> => {
  await app.close();
  await pool.end();
  process.exit(0);
};
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

await app.listen({ port: env.PORT, host: env.HOST });
