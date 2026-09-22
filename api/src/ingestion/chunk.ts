import type { PageText } from './pdf.js';

export interface Chunk {
  page: number;
  chunkIndex: number;
  text: string;
}

const TARGET_CHARS = 1200;
const OVERLAP_CHARS = 200;

/**
 * Chunks never span a page boundary. Retrieval returns the page a snippet came
 * from, and a chunk covering two pages could not be cited to either.
 */
export function chunkPages(pages: PageText[]): Chunk[] {
  const chunks: Chunk[] = [];
  let chunkIndex = 0;

  for (const page of pages) {
    for (const text of splitPage(page.text)) {
      chunks.push({ page: page.page, chunkIndex: chunkIndex++, text });
    }
  }
  return chunks;
}

function splitPage(text: string): string[] {
  const trimmed = text.trim();
  if (trimmed.length === 0) return [];
  if (trimmed.length <= TARGET_CHARS) return [trimmed];

  const parts: string[] = [];
  let cursor = 0;

  while (cursor < trimmed.length) {
    const end = Math.min(cursor + TARGET_CHARS, trimmed.length);
    const slice = trimmed.slice(cursor, end);
    const cut = end === trimmed.length ? slice.length : boundaryWithin(slice);

    parts.push(slice.slice(0, cut).trim());

    if (end === trimmed.length) break;
    // Overlap keeps a clause that straddles the cut retrievable from both sides.
    cursor += Math.max(cut - OVERLAP_CHARS, 1);
  }

  return parts.filter((p) => p.length > 0);
}

/**
 * Prefer breaking where the insurer did — paragraph, then sentence — so a chunk
 * rarely severs a clause mid-obligation. Falls back to the hard limit.
 */
function boundaryWithin(slice: string): number {
  const minimum = Math.floor(TARGET_CHARS * 0.5);

  const paragraph = slice.lastIndexOf('\n\n');
  if (paragraph >= minimum) return paragraph;

  const sentence = Math.max(
    slice.lastIndexOf('. '),
    slice.lastIndexOf('.\n'),
    slice.lastIndexOf('; '),
  );
  if (sentence >= minimum) return sentence + 1;

  const space = slice.lastIndexOf(' ');
  return space >= minimum ? space : slice.length;
}
