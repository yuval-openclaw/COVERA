import { pool } from '../db/pool.js';
import { documentKey, documentStore } from '../storage/index.js';

export type DeleteResult =
  | { deleted: true; documentsRemoved: number }
  | { deleted: false; failedDocumentIds: string[] };

/**
 * Deletes an account and everything in it: stored files, then every row.
 *
 * Used by the user's own "Delete my account".
 *
 * Blobs go first. If any fails, the rows are kept so a retry can still find the
 * keys; the reverse order would orphan encrypted files with nothing left
 * pointing at them.
 */
export async function deleteAccountData(
  userId: string,
  onBlobError: (documentId: string, error: unknown) => void = () => {},
): Promise<DeleteResult> {
  const { rows: documents } = await pool.query<{ id: string }>(
    `SELECT id FROM documents WHERE user_id = $1`,
    [userId],
  );

  const failedDocumentIds: string[] = [];
  for (const doc of documents) {
    try {
      await documentStore.delete(documentKey(userId, doc.id));
    } catch (error) {
      failedDocumentIds.push(doc.id);
      onBlobError(doc.id, error);
    }
  }
  if (failedDocumentIds.length > 0) return { deleted: false, failedDocumentIds };

  // Every child table cascades from users.id, so one delete clears sessions,
  // members, documents, pages, policies, chunks and claims together.
  await pool.query(`DELETE FROM users WHERE id = $1`, [userId]);
  return { deleted: true, documentsRemoved: documents.length };
}
