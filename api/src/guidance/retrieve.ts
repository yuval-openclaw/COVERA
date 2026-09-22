import { pool } from '../db/pool.js';
import { embedQuery, toVectorLiteral } from '../embeddings/index.js';

export interface RetrievedSnippet {
  documentId: string;
  policyId: string;
  page: number;
  text: string;
  filename: string;
  /** Page text came from transcription, so a citation against it is weaker. */
  ocr: boolean;
}

/**
 * Retrieval is scoped three ways and all three matter:
 *   user_id      — another account's policy must never enter a plan;
 *   superseded   — a replaced policy's caps would otherwise be quoted as current;
 *   page join    — every snippet must arrive knowing the page it can be cited to.
 */
export async function retrieveSnippets(
  userId: string,
  query: string,
  limit = 12,
): Promise<RetrievedSnippet[]> {
  const embedding = await embedQuery(query);

  const { rows } = await pool.query<{
    document_id: string;
    policy_id: string;
    page: number;
    text: string;
    original_filename: string;
    ocr: boolean | null;
  }>(
    `SELECT c.document_id, p.id AS policy_id, c.page, c.text,
            d.original_filename, dp.ocr
     FROM document_chunks c
     JOIN documents d ON d.id = c.document_id AND d.user_id = c.user_id
     JOIN policies  p ON p.document_id = c.document_id
                     AND p.user_id = c.user_id
                     AND p.superseded_by IS NULL
     LEFT JOIN document_pages dp ON dp.document_id = c.document_id AND dp.page = c.page
     WHERE c.user_id = $1 AND c.embedding IS NOT NULL
     ORDER BY c.embedding <=> $2
     LIMIT $3`,
    [userId, toVectorLiteral(embedding), limit],
  );

  return rows.map((r) => ({
    documentId: r.document_id,
    policyId: r.policy_id,
    page: r.page,
    text: r.text,
    filename: r.original_filename,
    ocr: r.ocr ?? false,
  }));
}

/** Page text for the documents a plan cited, used to verify its quotes. */
export async function loadPagesForUser(
  userId: string,
  documentIds: string[],
): Promise<Map<string, Map<number, string>>> {
  const index = new Map<string, Map<number, string>>();
  if (documentIds.length === 0) return index;

  // document_pages carries no user_id of its own, so ownership comes from the join.
  const { rows } = await pool.query<{ document_id: string; page: number; text: string }>(
    `SELECT dp.document_id, dp.page, dp.text
     FROM document_pages dp
     JOIN documents d ON d.id = dp.document_id
     WHERE d.user_id = $1 AND dp.document_id = ANY($2::uuid[])`,
    [userId, documentIds],
  );

  for (const row of rows) {
    const pages = index.get(row.document_id) ?? new Map<number, string>();
    pages.set(row.page, row.text);
    index.set(row.document_id, pages);
  }
  return index;
}

export async function insurerContacts(
  userId: string,
): Promise<{ policyId: string; insurer: string | null; phone: string | null }[]> {
  const { rows } = await pool.query<{ id: string; insurer: string | null; phone: string | null }>(
    `SELECT id,
            extraction -> 'insurer_name' ->> 'value' AS insurer,
            extraction -> 'claims_process' -> 'contact' -> 'phone' ->> 'value' AS phone
     FROM policies
     WHERE user_id = $1 AND superseded_by IS NULL`,
    [userId],
  );
  return rows.map((r) => ({ policyId: r.id, insurer: r.insurer, phone: r.phone }));
}
