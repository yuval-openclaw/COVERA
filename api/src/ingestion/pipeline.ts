import { createHash, randomUUID } from 'node:crypto';
import type { PoolClient } from 'pg';
import { embedDocuments, toVectorLiteral } from '../embeddings/index.js';
import { pool, withTransaction } from '../db/pool.js';
import type { ExtractedPolicy } from '../schema/policy.js';
import { documentKey, documentStore } from '../storage/index.js';
import { chunkPages } from './chunk.js';
import { dateOf } from './dates.js';
import { diffPolicies, type FieldChange } from './diff.js';
import { extractPolicy } from './extract.js';
import { ocrPages } from './ocr.js';
import { extractPdfPages, type PageText } from './pdf.js';

export interface IngestResult {
  documentId: string;
  policyId: string;
  /** Populated when this upload supersedes an earlier version of the same policy. */
  supersedes: string | null;
  changes: FieldChange[];
  ocrPageNumbers: number[];
  alreadyIngested: boolean;
  /** How many fields were kept as "unverified" rather than with a figure. */
  unverifiedFields: number;
}

export async function ingestPolicyDocument(params: {
  userId: string;
  filename: string;
  contentType: string;
  file: Buffer;
}): Promise<IngestResult> {
  const { userId, filename, contentType, file } = params;
  const sha256 = createHash('sha256').update(file).digest('hex');

  // Both sides are required: a document row without its policy is a partial
  // state, and short-circuiting on it would return an empty policy id as though
  // the upload had succeeded. Re-ingesting is the safe response.
  const existing = await pool.query<{ document_id: string; policy_id: string; ocr_pages: number[] }>(
    `SELECT d.id AS document_id,
            p.id AS policy_id,
            COALESCE(
              ARRAY(SELECT page FROM document_pages WHERE document_id = d.id AND ocr ORDER BY page),
              '{}'
            ) AS ocr_pages
     FROM documents d
     JOIN policies p ON p.document_id = d.id AND p.user_id = d.user_id
     WHERE d.user_id = $1 AND d.sha256 = $2 AND d.status = 'extracted'
     ORDER BY p.version DESC
     LIMIT 1`,
    [userId, sha256],
  );

  const found = existing.rows[0];
  if (found) {
    return {
      documentId: found.document_id,
      policyId: found.policy_id,
      supersedes: null,
      changes: [],
      ocrPageNumbers: found.ocr_pages,
      alreadyIngested: true,
      unverifiedFields: 0,
    };
  }

  const documentId = randomUUID();
  const key = documentKey(userId, documentId);
  await documentStore.put(key, file, contentType);

  await pool.query(
    `INSERT INTO documents (id, user_id, storage_key, original_filename, content_type, byte_size, sha256, status)
     VALUES ($1, $2, $3, $4, $5, $6, $7, 'extracting')`,
    [documentId, userId, key, filename, contentType, file.byteLength, sha256],
  );

  try {
    // Model calls take minutes, so no database transaction is held open across
    // them; the atomic write happens once all results are in hand.
    const { pages, needsOcr } = await extractPdfPages(file);
    const transcribed = await ocrPages(file, needsOcr);
    const resolved = mergePages(pages, transcribed);

    const policyId = randomUUID();
    const { policy, unverified } = await extractPolicy({ policyId, documentId, pdf: file, pages: resolved });

    const chunks = chunkPages(resolved);
    const embeddings = await embedDocuments(chunks.map((c) => c.text));

    const previous = await findPreviousVersion(userId, policy);
    const changes = previous ? diffPolicies(previous.extraction, policy) : [];

    await withTransaction(async (client) => {
      await persistPages(client, userId, documentId, resolved);
      await persistChunks(client, documentId, userId, chunks, embeddings);

      await client.query(
        `INSERT INTO policies (id, user_id, document_id, policy_group_id, version, policy_type, extraction, effective_date, renewal_date)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
        [
          policyId,
          userId,
          documentId,
          previous?.policyGroupId ?? randomUUID(),
          (previous?.version ?? 0) + 1,
          policy.policy_type,
          policy,
          dateOf(policy.effective_date),
          dateOf(policy.renewal_date),
        ],
      );

      if (previous) {
        await client.query('UPDATE policies SET superseded_by = $1 WHERE id = $2', [
          policyId,
          previous.policyId,
        ]);
      }

      await client.query(
        `UPDATE documents SET status = 'extracted', page_count = $3
         WHERE id = $2 AND user_id = $1`,
        [userId, documentId, resolved.length],
      );
    });

    return {
      documentId,
      policyId,
      supersedes: previous?.policyId ?? null,
      changes,
      ocrPageNumbers: transcribed.map((p) => p.page),
      alreadyIngested: false,
      unverifiedFields: unverified?.length ?? 0,
    };
  } catch (error) {
    // The transaction rolls back pages, chunks and the policy row, so nothing
    // half-extracted survives to be retrieved later as though it were verified.
    // The stored file is discarded too: an unreadable medical document is not
    // worth retaining, and the user still holds the original.
    await documentStore.delete(key).catch(() => undefined);
    await pool.query(
      `UPDATE documents SET status = 'failed', failure_reason = $3
       WHERE id = $2 AND user_id = $1`,
      [userId, documentId, error instanceof Error ? error.message : 'Unknown extraction failure'],
    );
    throw error;
  }
}

function mergePages(fromTextLayer: PageText[], fromOcr: PageText[]): PageText[] {
  const byPage = new Map(fromOcr.map((p) => [p.page, p]));
  return fromTextLayer.map((page) => byPage.get(page.page) ?? page);
}

/** Only a stated policy number identifies a renewal; inference would mismerge. */
async function findPreviousVersion(
  userId: string,
  policy: ExtractedPolicy,
): Promise<{ policyId: string; policyGroupId: string; version: number; extraction: ExtractedPolicy } | null> {
  if (policy.policy_number.status !== 'stated') return null;

  const result = await pool.query<{
    id: string;
    policy_group_id: string;
    version: number;
    extraction: ExtractedPolicy;
  }>(
    `SELECT id, policy_group_id, version, extraction
     FROM policies
     WHERE user_id = $1
       AND policy_type = $2
       AND superseded_by IS NULL
       AND extraction -> 'policy_number' ->> 'value' = $3
     ORDER BY version DESC
     LIMIT 1`,
    [userId, policy.policy_type, policy.policy_number.value],
  );

  const row = result.rows[0];
  return row
    ? {
        policyId: row.id,
        policyGroupId: row.policy_group_id,
        version: row.version,
        extraction: row.extraction,
      }
    : null;
}

async function persistPages(
  client: PoolClient,
  userId: string,
  documentId: string,
  pages: PageText[],
): Promise<void> {
  for (const page of pages) {
    // document_pages has no user_id column of its own, so ownership is
    // re-derived here from documents. If the document is not this user's, the
    // statement writes nothing instead of attaching page text to another
    // account's file.
    await client.query(
      `INSERT INTO document_pages (document_id, page, text, ocr)
       SELECT d.id, $3, $4, $5 FROM documents d WHERE d.id = $2 AND d.user_id = $1
       ON CONFLICT (document_id, page) DO UPDATE SET text = EXCLUDED.text, ocr = EXCLUDED.ocr`,
      [userId, documentId, page.page, page.text, page.ocr],
    );
  }
}

async function persistChunks(
  client: PoolClient,
  documentId: string,
  userId: string,
  chunks: { page: number; chunkIndex: number; text: string }[],
  embeddings: number[][],
): Promise<void> {
  for (const [i, chunk] of chunks.entries()) {
    const embedding = embeddings[i];
    if (!embedding) throw new Error(`Missing embedding for chunk ${chunk.chunkIndex}`);
    await client.query(
      `INSERT INTO document_chunks (document_id, user_id, page, chunk_index, text, embedding)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [documentId, userId, chunk.page, chunk.chunkIndex, chunk.text, toVectorLiteral(embedding)],
    );
  }
}

