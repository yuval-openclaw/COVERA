import { normalize, numbersIn } from '../ingestion/verify.js';
import { unsupportedFiguresIn } from './verify-steps.js';

interface Citation { document_id: string; page: number; verbatim_quote: string }
interface Answer { answer: string; citations: Citation[]; ask_insurer: string | null }

/** Env-free so it can be tested directly. */
export function checkAnswer(answer: Answer, pages: Map<string, Map<number, string>>): string[] {
  const problems: string[] = [];
  const supported = new Set<string>();

  for (const c of answer.citations) {
    const page = pages.get(c.document_id)?.get(c.page);
    if (page === undefined || !normalize(page).includes(normalize(c.verbatim_quote))) {
      problems.push(`a citation to page ${c.page} is not found on that page`);
      continue;
    }
    for (const n of numbersIn(c.verbatim_quote)) supported.add(n);
  }

  const figures = unsupportedFiguresIn(answer.answer, supported);
  if (figures.length) problems.push(`the answer states ${figures.join(', ')} without a citation containing it`);
  if (answer.ask_insurer && numbersIn(answer.ask_insurer).length) problems.push('ask_insurer contains a figure');
  return problems;
}
