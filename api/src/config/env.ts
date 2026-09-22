import { z } from 'zod';

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().positive().default(3000),
  DATABASE_URL: z.string().min(1),
  STORAGE_DRIVER: z.enum(['local', 's3']).default('local'),
  STORAGE_LOCAL_PATH: z.string().default('./storage'),
  S3_BUCKET: z.string().optional(),
  S3_REGION: z.string().optional(),
  // Deliberately not GEMINI_API_KEY: that name is frequently already exported by
  // developer tools, and Node's --env-file will not override an existing var —
  // the .env value would be silently ignored.
  COVERA_GEMINI_API_KEY: z.string().min(1),
  // Model names change faster than code; override here without a deploy.
  GEMINI_MODEL: z.string().min(1).default('gemini-2.5-pro'),
  GEMINI_FAST_MODEL: z.string().min(1).default('gemini-2.5-flash'),
  // The iOS OAuth client ID from Google Cloud. Unset means Google sign-in is off.
  GOOGLE_IOS_CLIENT_ID: z.string().optional(),
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
