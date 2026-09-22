import { pool } from '../db/pool.js';
import { documentKey, documentStore } from '../storage/index.js';

export type DeleteResult =
  | { deleted: true; documentsRemoved: number }
  | { deleted: false; failedDocumentIds: string[] };

/**
 * Deletes an account and everything in it: stored files, then every row.
 *
 * Shared by the user's own "Delete my account" and by the sweep that removes
 * guest accounts nobody can reach any more, so both erase exactly the same
 * things.
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

/**
 * Guest accounts have no password: the session token on the device is the only
 * key. Once every session for a guest has expired, no one can sign in to it
 * again, and keeping its health documents would be storage with no purpose and
 * no way for the owner to delete them. Those accounts are deleted.
 *
 * Sessions slide forward while an account is used (see requireUserId), so this
 * only reaches guests unused for the full session lifetime.
 */
export async function deleteUnreachableGuests(
  log: (message: string, detail: object) => void,
): Promise<number> {
  const { rows } = await pool.query<{ id: string }>(
    `SELECT u.id FROM users u
     WHERE u.email LIKE 'guest-%@guest.covera.invalid'
       AND u.password_hash IS NULL
       AND u.google_sub IS NULL
       AND u.created_at < now() - interval '1 day'
       AND NOT EXISTS (
         SELECT 1 FROM sessions s WHERE s.user_id = u.id AND s.expires_at > now()
       )`,
  );

  let removed = 0;
  for (const { id } of rows) {
    const result = await deleteAccountData(id, (documentId) =>
      log('guest blob delete failed', { documentId }),
    );
    if (result.deleted) removed += 1;
  }
  return removed;
}
