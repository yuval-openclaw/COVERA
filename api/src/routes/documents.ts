import type { FastifyInstance } from 'fastify';
import { pool } from '../db/pool.js';
import { ExtractionFailedError } from '../ingestion/extract.js';
import { ingestPolicyDocument } from '../ingestion/pipeline.js';
import { UnreadablePdfError } from '../ingestion/pdf.js';
import { documentKey, documentStore } from '../storage/index.js';
import { allow, DAY } from '../auth/rate-limit.js';
import { contentDisposition } from './filename.js';
import { requireConsent, requireUserId } from './auth.js';

const ACCEPTED_TYPES = new Set(['application/pdf']);

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function documentRoutes(app: FastifyInstance): Promise<void> {
  app.post('/documents', async (request, reply) => {
    const userId = await requireUserId(request);
    await requireConsent(userId);
    // Each request here is paid for at the AI provider; a daily cap per
    // account keeps one account from running up the bill.
    if (!(await allow(`upload:${userId}`, 20, DAY))) {
      return reply.status(429).send({ error: 'You have added the most documents Covera accepts in one day. Try again tomorrow.' });
    }
    const upload = await request.file();

    if (!upload) {
      return reply.status(400).send({ error: 'No file supplied' });
    }
    if (!ACCEPTED_TYPES.has(upload.mimetype)) {
      return reply
        .status(415)
        .send({ error: `Unsupported type ${upload.mimetype}. Upload a PDF.` });
    }

    const file = await upload.toBuffer();
    // The declared type is the client's word; the bytes are the file's. A file
    // that does not start as a PDF is refused before it is stored or sent to
    // the AI provider.
    if (!file.subarray(0, 5).equals(Buffer.from('%PDF-'))) {
      return reply.status(415).send({ error: 'This file is not a PDF. Upload a PDF.' });
    }

    try {
      const result = await ingestPolicyDocument({
        userId,
        filename: upload.filename,
        contentType: upload.mimetype,
        file,
      });

      return reply.status(result.alreadyIngested ? 200 : 201).send({
        document_id: result.documentId,
        policy_id: result.policyId,
        already_ingested: result.alreadyIngested,
        supersedes_policy_id: result.supersedes,
        changes: result.changes,
        // Pages read by transcription rather than an embedded text layer.
        // Citations on these pages are verified against our transcription.
        transcribed_pages: result.ocrPageNumbers,
        // Fields Covera found but could not prove against the page; they carry
        // no figure. The app says so rather than implying the policy is silent.
        unverified_fields: result.unverifiedFields,
      });
    } catch (error) {
      if (error instanceof UnreadablePdfError) {
        return reply.status(422).send({
          error: 'This PDF could not be opened. It may be damaged or password-protected. Try downloading it again from your insurer.',
        });
      }
      if (error instanceof ExtractionFailedError) {
        // The kind and page of each rejection is enough to see what went wrong.
        // The detail is not logged: it quotes the policy, and policy text is
        // health data that stays out of logs (see the redact list in server.ts).
        request.log.warn(
          {
            violations: error.violations.map((v) => ({ kind: v.kind, page: v.page })),
            schemaIssues: error.schemaIssues.length,
          },
          'extraction rejected by the citation verifier',
        );
        // A failed extraction the user can retry beats a plausible one they act on.
        return reply.status(422).send({
          error:
            'This document could not be read with enough confidence to quote it accurately. Nothing was saved. Try a clearer scan, or upload the original PDF from your insurer.',
          unverified_citations: error.violations.length,
          structural_problems: error.schemaIssues.length,
        });
      }
      throw error;
    }
  });

  app.get('/documents', async (request) => {
    const userId = await requireUserId(request);
    const { rows } = await pool.query(
      `SELECT id, original_filename, status, page_count, uploaded_at
       FROM documents WHERE user_id = $1 ORDER BY uploaded_at DESC`,
      [userId],
    );
    return { documents: rows };
  });

  // The original file, decrypted on the way out. The ownership check is the
  // WHERE clause, not the storage key — a key is guessable, a row is not.
  app.get<{ Params: { id: string } }>('/documents/:id/file', async (request, reply) => {
    const userId = await requireUserId(request);
    // The id column is a uuid, so anything that is not one is a 404, not a
    // database error surfacing as a 500. Checked before the query so a bad id
    // never reaches Postgres.
    if (!UUID.test(request.params.id)) return reply.status(404).send({ error: 'No such document.' });

    const { rows } = await pool.query<{ original_filename: string; content_type: string }>(
      `SELECT original_filename, content_type FROM documents WHERE id = $1 AND user_id = $2`,
      [request.params.id, userId],
    );
    const doc = rows[0];
    if (!doc) return reply.status(404).send({ error: 'No such document.' });

    const body = await documentStore.get(documentKey(userId, request.params.id));
    return reply
      .header('content-type', doc.content_type)
      .header('content-disposition', contentDisposition(doc.original_filename))
      .send(body);
  });
}
