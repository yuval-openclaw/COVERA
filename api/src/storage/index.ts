import { mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { dirname, join, resolve, sep } from 'node:path';
import { env } from '../config/env.js';
import { decrypt, encrypt } from './crypto.js';

export interface DocumentStore {
  put(key: string, body: Buffer, contentType: string): Promise<void>;
  get(key: string): Promise<Buffer>;
  delete(key: string): Promise<void>;
}

class LocalStore implements DocumentStore {
  constructor(private readonly root: string) {}

  private resolveKey(key: string): string {
    const base = resolve(this.root);
    const target = resolve(base, key);
    // Keys derive from request data, so confine them to the storage root.
    if (target !== base && !target.startsWith(base + sep)) {
      throw new Error('Resolved storage key escapes the storage root');
    }
    return target;
  }

  async put(key: string, body: Buffer): Promise<void> {
    const path = this.resolveKey(key);
    await mkdir(dirname(path), { recursive: true });
    await writeFile(path, encrypt(body), { mode: 0o600 });
  }

  async get(key: string): Promise<Buffer> {
    return decrypt(await readFile(this.resolveKey(key)));
  }

  async delete(key: string): Promise<void> {
    await rm(this.resolveKey(key), { force: true });
  }
}

class S3Store implements DocumentStore {
  constructor(
    private readonly bucket: string,
    private readonly region: string,
    private readonly endpoint?: string,
  ) {}

  private async client() {
    const { S3Client } = await import('@aws-sdk/client-s3');
    return new S3Client(
      this.endpoint ? { region: this.region, endpoint: this.endpoint } : { region: this.region },
    );
  }

  async put(key: string, body: Buffer, contentType: string): Promise<void> {
    const { PutObjectCommand } = await import('@aws-sdk/client-s3');
    const client = await this.client();
    await client.send(
      new PutObjectCommand({
        Bucket: this.bucket,
        Key: key,
        Body: encrypt(body),
        ContentType: contentType,
      }),
    );
  }

  async get(key: string): Promise<Buffer> {
    const { GetObjectCommand } = await import('@aws-sdk/client-s3');
    const client = await this.client();
    const response = await client.send(
      new GetObjectCommand({ Bucket: this.bucket, Key: key }),
    );
    if (!response.Body) throw new Error(`Empty body for ${key}`);
    return decrypt(Buffer.from(await response.Body.transformToByteArray()));
  }

  async delete(key: string): Promise<void> {
    const { DeleteObjectCommand } = await import('@aws-sdk/client-s3');
    const client = await this.client();
    await client.send(new DeleteObjectCommand({ Bucket: this.bucket, Key: key }));
  }
}

export const documentStore: DocumentStore =
  env.STORAGE_DRIVER === 's3'
    ? new S3Store(env.S3_BUCKET!, env.S3_REGION ?? 'us-east-1', env.S3_ENDPOINT)
    : new LocalStore(env.STORAGE_LOCAL_PATH);

/** Keys are user-scoped so a leaked key cannot enumerate other accounts. */
export function documentKey(userId: string, documentId: string): string {
  return join('users', userId, 'documents', documentId);
}
