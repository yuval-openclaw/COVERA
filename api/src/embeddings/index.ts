import { GEMINI_BASE } from '../ai/gemini.js';
import { env } from '../config/env.js';

const MODEL = 'gemini-embedding-001';

/**
 * Must match document_chunks.embedding; a mismatch fails at insert, not
 * silently. 768 is one of the sizes Google recommends for this model's reduced
 * output, and cosine distance in pgvector does not need the vectors normalised.
 */
export const EMBEDDING_DIMENSIONS = 768;

/** batchEmbedContents accepts at most 100 requests per call. */
const MAX_BATCH = 100;

type TaskType = 'RETRIEVAL_DOCUMENT' | 'RETRIEVAL_QUERY';

/**
 * Retrieval ranks better when the model knows whether text is stored content
 * or a search query, so the two call sites are distinguished.
 */
async function embed(texts: string[], taskType: TaskType): Promise<number[][]> {
  if (texts.length === 0) return [];

  const response = await fetch(`${GEMINI_BASE}/models/${MODEL}:batchEmbedContents`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-goog-api-key': env.COVERA_GEMINI_API_KEY },
    body: JSON.stringify({
      requests: texts.map((text) => ({
        model: `models/${MODEL}`,
        content: { parts: [{ text }] },
        taskType,
        outputDimensionality: EMBEDDING_DIMENSIONS,
      })),
    }),
  });

  if (!response.ok) {
    throw new Error(`Gemini embedding failed (${response.status}): ${(await response.text()).slice(0, 400)}`);
  }

  const body = (await response.json()) as { embeddings?: { values: number[] }[] };
  const embeddings = body.embeddings ?? [];

  // Results come back in request order; a short list means a chunk would be
  // stored against the wrong vector, so it is an error, not a partial success.
  if (embeddings.length !== texts.length) {
    throw new Error(`Gemini returned ${embeddings.length} embeddings for ${texts.length} inputs`);
  }
  for (const embedding of embeddings) {
    if (embedding.values.length !== EMBEDDING_DIMENSIONS) {
      throw new Error(`Expected ${EMBEDDING_DIMENSIONS} dimensions, received ${embedding.values.length}`);
    }
  }
  return embeddings.map((e) => e.values);
}

export async function embedDocuments(texts: string[]): Promise<number[][]> {
  const results: number[][] = [];
  for (let i = 0; i < texts.length; i += MAX_BATCH) {
    results.push(...(await embed(texts.slice(i, i + MAX_BATCH), 'RETRIEVAL_DOCUMENT')));
  }
  return results;
}

export async function embedQuery(text: string): Promise<number[]> {
  const [embedding] = await embed([text], 'RETRIEVAL_QUERY');
  if (!embedding) throw new Error('Gemini returned no embedding for query');
  return embedding;
}

/** pgvector accepts its literal form over the wire, not a JS array. */
export function toVectorLiteral(embedding: number[]): string {
  return `[${embedding.join(',')}]`;
}
