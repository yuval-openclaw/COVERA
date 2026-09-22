import { describe, expect, it } from 'vitest';
import { supportedNumbers, unsupportedFiguresIn, verifySteps } from './verify-steps.js';
import type { ActionStep } from './schema.js';

const DOC = '11111111-1111-4111-8111-111111111111';

const pages = new Map<string, Map<number, string>>([
  [
    DOC,
    new Map<number, string>([
      [
        4,
        'Section 12 — Surgery. The Fund reimburses 80% of the surgeon fee, up to 20,000 per event. A claim must be submitted within 90 days of the operation.',
      ],
    ]),
  ],
]);

function step(partial: Partial<ActionStep>): ActionStep {
  return {
    order: 1,
    action: 'Call the insurer.',
    deadline_note: null,
    basis: { kind: 'general' },
    ...partial,
  } as ActionStep;
}

function cited(quote: string, page = 4, document_id = DOC) {
  return {
    kind: 'cited' as const,
    citation: { document_id, page, clause_ref: null, verbatim_quote: quote },
  };
}

describe('verifySteps', () => {
  it('passes a cited step whose figure appears in its own quote', () => {
    const steps = [
      step({
        action: 'Submit the claim within 90 days of the operation.',
        basis: cited('A claim must be submitted within 90 days of the operation.'),
      }),
    ];
    expect(verifySteps(steps, pages)).toEqual([]);
  });

  it('withholds a step citing a page that is not in the user documents', () => {
    const steps = [
      step({
        action: 'Submit within 90 days.',
        basis: cited('A claim must be submitted within 90 days of the operation.', 99),
      }),
    ];
    const failures = verifySteps(steps, pages);
    expect(failures).toHaveLength(1);
    expect(failures[0]?.reason).toContain('not in your documents');
  });

  it('withholds a step citing another document', () => {
    const steps = [
      step({
        action: 'Submit within 90 days.',
        basis: cited(
          'A claim must be submitted within 90 days of the operation.',
          4,
          '22222222-2222-4222-8222-222222222222',
        ),
      }),
    ];
    expect(verifySteps(steps, pages)[0]?.reason).toContain('not in your documents');
  });

  it('withholds a step whose quote does not appear on the cited page', () => {
    const steps = [
      step({
        action: 'Submit within 30 days.',
        basis: cited('A claim must be submitted within 30 days of the operation.'),
      }),
    ];
    expect(verifySteps(steps, pages)[0]?.reason).toContain('does not appear on page 4');
  });

  // The dangerous case: a real quote from a real page, paired with a figure the
  // quote never contained.
  it('withholds a step asserting a figure absent from its own quote', () => {
    const steps = [
      step({
        action: 'You will be reimbursed 100% of the surgeon fee.',
        basis: cited('The Fund reimburses 80% of the surgeon fee'),
      }),
    ];
    expect(verifySteps(steps, pages)[0]?.reason).toContain('100');
  });

  it('checks the deadline note as well as the action', () => {
    const steps = [
      step({
        action: 'Submit the claim form.',
        deadline_note: 'Within 45 days.',
        basis: cited('A claim must be submitted within 90 days of the operation.'),
      }),
    ];
    expect(verifySteps(steps, pages)[0]?.reason).toContain('45');
  });

  it('withholds an uncited step that smuggles in a figure', () => {
    const steps = [
      step({ action: 'Expect to pay a 250 excess at the hospital desk.' }),
      step({
        order: 2,
        action: 'Ask about the waiting period.',
        basis: { kind: 'not_stated', ask_insurer: 'Is there a 90 day wait?', insurer_phone: null },
      }),
    ];
    const failures = verifySteps(steps, pages);
    expect(failures).toHaveLength(2);
    expect(failures[0]?.reason).toContain('without citing');
  });

  it('does not let a withheld step lend its figures to the prose', () => {
    const steps = [
      step({
        action: 'You will be reimbursed 100% of the surgeon fee.',
        basis: cited('The Fund reimburses 80% of the surgeon fee'),
      }),
    ];
    const failures = verifySteps(steps, pages);
    // The step is withheld, so nothing it quoted is available to the summary.
    expect(supportedNumbers(steps, failures).size).toBe(0);
  });

  it('allows procedural steps that assert no figure', () => {
    const steps = [
      step({ action: 'Bring photo ID and keep the original receipt.' }),
      step({
        order: 2,
        action: 'Ask your insurer whether a referral is required.',
        basis: {
          kind: 'not_stated',
          ask_insurer: 'Is a referral required before surgery?',
          insurer_phone: '*2700',
        },
      }),
    ];
    expect(verifySteps(steps, pages)).toEqual([]);
  });
});

describe('prose may only repeat figures the steps proved', () => {
  const steps = [
    step({
      action: 'Submit the claim within 90 days of the operation.',
      basis: cited('A claim must be submitted within 90 days of the operation.'),
    }),
    step({
      order: 2,
      action: 'Ask the hospital for an itemised invoice.',
    }),
  ];
  const supported = supportedNumbers(steps, verifySteps(steps, pages));

  it('collects the figures from surviving citations', () => {
    expect(supported.has('90')).toBe(true);
  });

  it('passes a summary that repeats a proved figure', () => {
    expect(
      unsupportedFiguresIn('You have 90 days from the operation to claim.', supported),
    ).toEqual([]);
  });

  it('catches a figure the summary invented', () => {
    // The dangerous shape: a correct-looking paragraph at the top of the screen,
    // asserting a reimbursement rate no step ever cited.
    expect(
      unsupportedFiguresIn('You have 90 days, and 80% of the fee is covered.', supported),
    ).toEqual(['80']);
  });

  it('lets a claim email use placeholders but not an invented amount', () => {
    const withPlaceholders =
      'I am claiming [amount] for the operation on [date]. Policy [policy number]. Submitted within 90 days.';
    expect(unsupportedFiguresIn(withPlaceholders, supported)).toEqual([]);

    // The email goes to the insurer; a guessed sum in it is one the user will
    // be held to.
    const withGuess = 'I am claiming 12,400 for the operation, submitted within 90 days.';
    expect(unsupportedFiguresIn(withGuess, supported)).toEqual(['12400']);
  });

  it('ignores prose with no figures at all', () => {
    expect(unsupportedFiguresIn('Call your insurer before the operation.', supported)).toEqual([]);
  });
});
