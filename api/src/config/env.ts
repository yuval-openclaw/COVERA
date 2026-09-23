import { z } from 'zod';

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().positive().default(3000),
  // 127.0.0.1 on a laptop; a container must listen on 0.0.0.0 to be reachable.
  HOST: z.string().min(1).default('127.0.0.1'),
  // The number of proxies in front of the app, or "false" when it is exposed
  // directly. This is the *hop count*, not a boolean: with plain `true`,
  // Fastify would take the left-most X-Forwarded-For entry, which the client
  // writes, so anyone could forge a fresh IP per request and walk past every
  // per-address rate limit. A hop count makes it count in from the right — past
  // exactly the proxies we trust — to the address the proxy actually saw.
  // Fly.io and most single-proxy hosts are "1". "false" leaves req.ip as the
  // socket address, correct only with no proxy at all.
  TRUST_PROXY: z
    .string()
    .default('false')
    .refine((v) => v === 'false' || /^[1-9]\d*$/.test(v), {
      message: 'TRUST_PROXY must be "false" or a positive integer (the number of proxies in front)',
    }),
  DATABASE_URL: z.string().min(1),
  STORAGE_DRIVER: z.enum(['local', 's3']).default('local'),
  STORAGE_LOCAL_PATH: z.string().default('./storage'),
  S3_BUCKET: z.string().optional(),
  S3_REGION: z.string().optional(),
  // For S3-compatible storage (Cloudflare R2, Backblaze B2 and others).
  S3_ENDPOINT: z.string().url().optional(),
  // Deliberately not GEMINI_API_KEY: that name is frequently already exported by
  // developer tools, and Node's --env-file will not override an existing var —
  // the .env value would be silently ignored.
  COVERA_GEMINI_API_KEY: z.string().min(1),
  // Model names change faster than code; override here without a deploy.
  GEMINI_MODEL: z.string().min(1).default('gemini-2.5-pro'),
  GEMINI_FAST_MODEL: z.string().min(1).default('gemini-2.5-flash'),
  // The iOS OAuth client ID from Google Cloud. Unset means Google sign-in is off.
  GOOGLE_IOS_CLIENT_ID: z.string().optional(),
  // The audience Apple puts in an identity token for a native app: the bundle
  // identifier. Public, and fixed for this app, so it needs no setting.
  APPLE_BUNDLE_ID: z.string().min(1).default('com.covera.app'),
  DOCUMENT_ENCRYPTION_KEY: z
    .string()
    .regex(/^[0-9a-f]{64}$/i, 'DOCUMENT_ENCRYPTION_KEY must be 32 bytes of hex'),
});

function load() {
  const parsed = envSchema.safeParse(process.env);
  if (!parsed.success) {
    const issues = parsed.error.issues.map((i) => `  ${i.path.join('.')}: ${i.message}`);
    throw new Error(`Invalid environment configuration:\n${issues.join('\n')}`);
  }
  if (parsed.data.STORAGE_DRIVER === 's3' && !parsed.data.S3_BUCKET) {
    throw new Error('S3_BUCKET is required when STORAGE_DRIVER=s3');
  }
  return parsed.data;
}

export const env = load();
