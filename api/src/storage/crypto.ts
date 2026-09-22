import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import { env } from '../config/env.js';

/**
 * Documents are encrypted by the application before they reach any storage
 * driver, so at-rest protection does not depend on the disk or bucket being
 * configured correctly.
 *
 * Layout: [12-byte IV][16-byte auth tag][ciphertext]
 */

const IV_BYTES = 12;
const TAG_BYTES = 16;
const key = Buffer.from(env.DOCUMENT_ENCRYPTION_KEY, 'hex');

export function encrypt(plaintext: Buffer): Buffer {
  const iv = randomBytes(IV_BYTES);
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  return Buffer.concat([iv, cipher.getAuthTag(), ciphertext]);
}

export function decrypt(payload: Buffer): Buffer {
  if (payload.length < IV_BYTES + TAG_BYTES) {
    throw new Error('Ciphertext is too short to be valid');
  }
  const iv = payload.subarray(0, IV_BYTES);
  const tag = payload.subarray(IV_BYTES, IV_BYTES + TAG_BYTES);
  const decipher = createDecipheriv('aes-256-gcm', key, iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(payload.subarray(IV_BYTES + TAG_BYTES)), decipher.final()]);
}
