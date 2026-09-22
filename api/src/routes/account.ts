import type { FastifyInstance } from 'fastify';
import { pool } from '../db/pool.js';
import { deleteAccountData } from '../account/delete.js';
import { requireUserId } from './auth.js';

/**
 * Export and erasure.
 *
 * Both are user rights under GDPR-style regimes, and in-app account deletion is
 * an App Store requirement (Guideline 5.1.1(v)) rather than a nice-to-have. Both
 * are scoped by user_id in every statement — nothing here takes an id from the
 * request body and trusts it.
 */
export async function accountRoutes(app: FastifyInstance): Promise<void> {
  // Everything we hold about this account, in one JSON document. Policy
  // extractions are returned whole, citations included, so an export is useful
  // to a person switching insurer or arguing with one.
  app.get('/account/export', async (request, reply) => {
    const userId = await requireUserId(request);

    const [account, members, documents, policies, chunks, claims] = await Promise.all([
      pool.query(
        `SELECT id, email, created_at, health_consent_at, health_consent_version
         FROM users WHERE id = $1 AND deleted_at IS NULL`,
        [userId],
      ),
      pool.query(
        `SELECT id, display_name, date_of_birth, relationship, created_at
         FROM members WHERE user_id = $1 ORDER BY created_at`,
        [userId],
      ),
      pool.query(
        `SELECT id, original_filename, content_type, byte_size, page_count, status,
                failure_reason, uploaded_at
         FROM documents WHERE user_id = $1 ORDER BY uploaded_at`,
        [userId],
      ),
      pool.query(
        `SELECT id, document_id, policy_group_id, version, policy_type, extraction,
                effective_date, renewal_date, superseded_by, created_at
         FROM policies WHERE user_id = $1 ORDER BY created_at`,
        [userId],
      ),
      // The extracted text, but not the embeddings: a 1024-float vector per
      // chunk is noise to a human and bulk to a download.
      pool.query(
        `SELECT document_id, page, chunk_index, text
         FROM document_chunks WHERE user_id = $1
         ORDER BY document_id, page, chunk_index`,
        [userId],
      ),
      pool.query(
        `SELECT id, member_id, policy_id, title, status, submitted_at, deadline_at,
                amount_claimed, amount_reimbursed, created_at
         FROM claims WHERE user_id = $1 ORDER BY created_at`,
        [userId],
      ),
    ]);

    if (account.rowCount === 0) {
      return reply.status(404).send({ error: 'No such account.' });
    }

    return reply
      .header('content-disposition', 'attachment; filename="covera-export.json"')
      .send({
        exported_at: new Date().toISOString(),
        // The original files are not inlined; they are fetched per document so a
        // large library does not have to be base64'd into one response.
        note: 'Original uploaded files are downloadable individually at /documents/:id/file.',
        account: account.rows[0],
        members: members.rows,
        documents: documents.rows,
        policies: policies.rows,
        document_text: chunks.rows,
        claims: claims.rows,
      });
  });

  // Records that this account agreed to the processing of health information
  // described in the privacy policy, and which version it agreed to. Called by
  // the app after the consent screen; repeating it with the same version is
  // harmless, and a new version overwrites the old record.
  app.post('/account/consent', async (request, reply) => {
    const userId = await requireUserId(request);
    const version = (request.body as { version?: unknown } | undefined)?.version;
    if (typeof version !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(version)) {
      return reply.status(400).send({ error: 'version must be a date like 2026-09-21' });
    }
    await pool.query(
      `UPDATE users SET health_consent_at = now(), health_consent_version = $1
       WHERE id = $2 AND deleted_at IS NULL`,
      [version, userId],
    );
    return { recorded: true, version };
  });

  app.delete('/account', async (request, reply) => {
    const userId = await requireUserId(request);

    const result = await deleteAccountData(userId, (documentId, error) =>
      request.log.error({ err: error, documentId }, 'blob delete failed'),
    );
    if (!result.deleted) {
      return reply.status(500).send({
        error:
          'Some stored files could not be deleted, so the account was left intact. Try again; nothing was partially removed.',
      });
    }

    return reply.status(200).send({
      deleted: true,
      documents_removed: result.documentsRemoved,
      message: 'Your account, your documents and everything extracted from them are gone.',
    });
  });
}
