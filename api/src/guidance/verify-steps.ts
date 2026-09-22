import { normalize, numbersIn } from '../ingestion/verify.js';
import type { ActionStep } from './schema.js';

export interface StepFailure {
  step: ActionStep;
  reason: string;
}

/**
 * The last gate before guidance reaches a user. A step may assert a figure only
 * if it cites text that actually contains that figure; anything else is
 * withheld rather than shown with a caveat, because a wrong number during a
 * medical crisis is worse than a missing one.
 *
 * Kept free of database and API imports so it stays directly testable.
 */
export function verifySteps(
  steps: ActionStep[],
  pages: Map<string, Map<number, string>>,
): StepFailure[] {
  const failures: StepFailure[] = [];

  for (const step of steps) {
    const asserted = numbersIn(`${step.action} ${step.deadline_note ?? ''}`);

    if (step.basis.kind !== 'cited') {
      // An uncited step may describe procedure, but it may not carry figures.
      // The question put to the insurer counts too: "is the 90-day wait waived?"
      // asserts a 90-day wait as surely as a sentence would.
      const inQuestion =
        step.basis.kind === 'not_stated' ? numbersIn(step.basis.ask_insurer) : [];
      if (asserted.length > 0 || inQuestion.length > 0) {
        failures.push({
          step,
          reason: 'it states a figure without citing the document it came from',
        });
      }
      continue;
    }

    const { citation } = step.basis;
    const pageText = pages.get(citation.document_id)?.get(citation.page);

    if (pageText === undefined) {
      failures.push({ step, reason: 'it cites a page that is not in your documents' });
      continue;
    }

    if (!normalize(pageText).includes(normalize(citation.verbatim_quote))) {
      failures.push({
        step,
        reason: `the quoted wording does not appear on page ${citation.page}`,
      });
      continue;
    }

    const supported = new Set(numbersIn(citation.verbatim_quote));
    const missing = asserted.filter((n) => !supported.has(n));
    if (missing.length > 0) {
      failures.push({
        step,
        reason: `it states ${missing.join(', ')}, which the quoted text does not contain`,
      });
    }
  }

  return failures;
}

/**
 * The numbers a plan has earned the right to repeat: everything appearing in a
 * citation quote that survived verification.
 */
export function supportedNumbers(
  steps: ActionStep[],
  failed: StepFailure[],
): Set<string> {
  const withheld = new Set(failed.map((f) => f.step.order));
  const supported = new Set<string>();

  for (const step of steps) {
    if (withheld.has(step.order) || step.basis.kind !== 'cited') continue;
    for (const number of numbersIn(step.basis.citation.verbatim_quote)) {
      supported.add(number);
    }
  }
  return supported;
}

/**
 * Prose carries no citation of its own, so it may only repeat figures the steps
 * already proved. Without this, the summary is a hole straight through the
 * citation guarantee: a paragraph at the top of the screen saying "you will be
 * reimbursed 90%" is exactly what a frightened reader takes away, and until now
 * nothing checked it.
 *
 * Returns the unsupported figures, empty when the prose is safe.
 */
export function unsupportedFiguresIn(text: string, supported: Set<string>): string[] {
  return [...new Set(numbersIn(text))].filter((n) => !supported.has(n));
}
