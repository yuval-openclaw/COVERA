import type { ExtractedPolicy } from '../schema/policy.js';
import { normalize, numbersIn, type PageIndex } from './verify.js';

/**
 * Replaces a model's quote with the exact text of the page, when the model
 * clearly meant that passage but did not reproduce it character for character.
 *
 * Why this is needed: in Hebrew and Arabic PDFs the stored text layer often
 * runs in a different order from the printed line ("824142717 מס' פוליסה:" is
 * stored for a line printed as "מס' פוליסה: 824142717"), and the model reads
 * the printed page. Its quote has the right words and the right figures in the
 * wrong order, and the verifier — correctly — cannot find it.
 *
 * Why this does not weaken the guarantee: nothing here decides that a quote is
 * good. It only swaps the model's wording for real page text, and only when
 * that page text contains every figure in the model's quote and nearly all of
 * its words. The verifier then runs unchanged on the page text: the quote must
 * appear on the page (it does, by construction) and every figure in the value
 * must appear in the quote. A quote the page does not support is not snapped,
 * and fails exactly as before.
 */
export function snapQuotesToPages(policy: ExtractedPolicy, pages: PageIndex): number {
  let snapped = 0;

  const visit = (node: unknown): void => {
    if (Array.isArray(node)) {
      node.forEach(visit);
      return;
    }
    if (node === null || typeof node !== 'object') return;
    const record = node as Record<string, unknown>;

    const citation = record['source_citation'] as
      | { document_id?: unknown; page?: unknown; verbatim_quote?: unknown }
      | undefined;
    if (
      citation &&
      typeof citation.document_id === 'string' &&
      typeof citation.page === 'number' &&
      typeof citation.verbatim_quote === 'string'
    ) {
      const pageText = pages.get(citation.document_id)?.get(citation.page);
      if (pageText !== undefined) {
        const replacement = snapQuote(citation.verbatim_quote, pageText);
        if (replacement !== null) {
          citation.verbatim_quote = replacement;
          snapped += 1;
        }
      }
    }

    Object.values(record).forEach(visit);
  };

  visit(policy);
  return snapped;
}

/** How much of the quote's wording the page passage must contain. */
const MIN_RECALL = 0.85;
/** How much of the page passage must be the quote, so a whole page cannot match. */
const MIN_PRECISION = 0.5;
/** Quotes shorter than this carry too little to identify a passage safely. */
const MIN_TOKENS = 3;
/** Printed lines one quote may span. */
const MAX_LINES = 4;

/**
 * The exact page text the quote corresponds to, or null when the quote already
 * matches, or when no passage matches closely enough to be sure.
 */
export function snapQuote(quote: string, pageText: string): string | null {
  if (normalize(pageText).includes(normalize(quote))) return null;

  const quoteTokens = tokens(quote);
  if (quoteTokens.length < MIN_TOKENS) return null;
  const quoteNumbers = new Set(numbersIn(quote));

  const lines = pageText.split(/\r?\n/).map((l) => l.trim()).filter((l) => l.length > 0);
  let best: { text: string; score: number; size: number } | null = null;

  for (let start = 0; start < lines.length; start++) {
    for (let span = 1; span <= MAX_LINES && start + span <= lines.length; span++) {
      const text = lines.slice(start, start + span).join(' ');
      const windowTokens = tokens(text);

      // Every figure the model quoted must be printed in the passage. This is
      // the part that matters most: a snap may fix word order, never a number.
      const windowNumbers = new Set(numbersIn(text));
      if ([...quoteNumbers].some((n) => !windowNumbers.has(n))) continue;

      const overlap = multisetOverlap(quoteTokens, windowTokens);
      const recall = overlap / quoteTokens.length;
      const precision = overlap / windowTokens.length;
      if (recall < MIN_RECALL || precision < MIN_PRECISION) continue;

      const score = recall + precision;
      if (!best || score > best.score || (score === best.score && windowTokens.length < best.size)) {
        best = { text, score, size: windowTokens.length };
      }
    }
  }

  // Invisible direction marks are dropped: they carry no content (the verifier
  // ignores them too) and would otherwise end up inside quotes shown to users.
  return best ? best.text.replace(INVISIBLE_MARKS, '').replace(/\s+/g, ' ').trim() : null;
}

const INVISIBLE_MARKS = /[​-‏‪-‮⁦-⁩؜﻿]/g;

/**
 * Words and numbers, compared loosely: case, accents, Hebrew vowel points and
 * punctuation (including geresh and gershayim, which are typed several ways)
 * are dropped. Numbers keep their canonical form so 1,500 still equals 1500.
 */
function tokens(text: string): string[] {
  // Direction marks sometimes stand where a space should be ("פוליסה" glued to
  // "55012345"), so they separate words here, and a word running straight into
  // a number is split at the boundary.
  return normalize(text.replace(INVISIBLE_MARKS, ' '))
    .normalize('NFKD')
    // Combining accents (U+0300-036F) and Hebrew points and cantillation
    // (U+0591-05C7) only; letters of every script are kept.
    .replace(/[̀-֑ͯ-ׇ]/g, '')
    .replace(/(\p{L})(?=\d)/gu, '$1 ')
    .replace(/(\d)(?=\p{L})/gu, '$1 ')
    .split(/\s+/)
    .map((token) =>
      /\d/.test(token)
        ? (numbersIn(token)[0] ?? '')
        : token.replace(/[^\p{L}\p{N}]/gu, ''),
    )
    .filter((token) => token.length > 0);
}

function multisetOverlap(a: string[], b: string[]): number {
  const counts = new Map<string, number>();
  for (const t of b) counts.set(t, (counts.get(t) ?? 0) + 1);
  let overlap = 0;
  for (const t of a) {
    const left = counts.get(t) ?? 0;
    if (left > 0) {
      overlap += 1;
      counts.set(t, left - 1);
    }
  }
  return overlap;
}
