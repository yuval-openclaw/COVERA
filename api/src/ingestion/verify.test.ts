import { describe, expect, it } from 'vitest';
import { extractedPolicySchema, type ExtractedPolicy, type PolicyField } from '../schema/policy.js';
import { verifyPolicyCitations, type PageIndex } from './verify.js';

const DOC = '11111111-1111-4111-8111-111111111111';
const POLICY = '22222222-2222-4222-8222-222222222222';

const PAGE_4 = `Surgical procedures performed in-network are reimbursed at 80% of the
recognised tariff, up to an annual limit of 15,000 per insured member.`;

function stated(value: string, quote: string, page = 4): PolicyField {
  return {
    status: 'stated',
    value,
    normalized: null,
    source_citation: { document_id: DOC, page, clause_ref: '4.2', verbatim_quote: quote },
    extraction_confidence: 'high',
  };
}

const notStated: PolicyField = { status: 'not_stated', note: null };

function policyWith(field: PolicyField): ExtractedPolicy {
  return {
    policy_id: POLICY,
    insurer_name: stated('Example Assurance', 'Example Assurance', 1),
    policy_type: 'private_health',
    policy_number: notStated,
    insured_members: [],
    effective_date: notStated,
    renewal_date: notStated,
    coverage_items: [
      {
        category: 'surgery',
        coverage_percentage_or_amount: field,
        annual_limit: notStated,
        per_event_limit: notStated,
        deductible_or_copay: notStated,
        waiting_period_days: notStated,
        requires_preauthorization: notStated,
        network_restriction: notStated,
        exclusions: [],
      },
    ],
    claims_process: {
      steps: [],
      required_documents: [],
      submission_deadline_days: notStated,
      contact: { phone: notStated, email: notStated, portal_url: notStated },
    },
  };
}

const pages: PageIndex = new Map([
  [
    DOC,
    new Map([
      [1, 'Example Assurance — Policy Schedule'],
      [4, PAGE_4],
    ]),
  ],
]);

describe('citation verification', () => {
  it('accepts a figure whose quote appears on the cited page', () => {
    const policy = policyWith(stated('80%', 'reimbursed at 80% of the recognised tariff'));
    expect(verifyPolicyCitations(policy, pages)).toEqual([]);
  });

  it('matches a Hebrew quote across the invisible direction marks a PDF carries', () => {
    // Hebrew text layers wrap runs in RLE/PDF marks; they render as nothing,
    // so a quote that differs only by them is still the same text.
    const hebrew = '\u202bההשתתפות העצמית היא 80% מהתעריף המוכר\u202c';
    const policy = policyWith(stated('80%', 'ההשתתפות העצמית היא 80% מהתעריף המוכר'));
    const hebrewPages: PageIndex = new Map([
      [DOC, new Map([[1, 'Example Assurance — Policy Schedule'], [4, hebrew]])],
    ]);
    expect(verifyPolicyCitations(policy, hebrewPages)).toEqual([]);
  });

  it('supports an amount written with grouping commas and trailing decimal zeros', () => {
    const policy = policyWith(stated('1196454', 'up to 1,196,454.00 per policy year'));
    const withAmount: PageIndex = new Map([
      [DOC, new Map([[1, 'Example Assurance — Policy Schedule'], [4, 'up to 1,196,454.00 per policy year']])],
    ]);
    expect(verifyPolicyCitations(policy, withAmount)).toEqual([]);
  });

  it('rejects a quote that does not appear on the cited page', () => {
    const policy = policyWith(stated('90%', 'reimbursed at 90% of the recognised tariff'));
    const violations = verifyPolicyCitations(policy, pages);
    expect(violations.map((v) => v.kind)).toContain('quote_not_found');
  });

  it('rejects a real quote paired with a number the quote never contained', () => {
    const policy = policyWith(stated('95%', 'reimbursed at 80% of the recognised tariff'));
    const violations = verifyPolicyCitations(policy, pages);
    expect(violations.map((v) => v.kind)).toContain('value_not_in_quote');
  });

  it('rejects a citation pointing at a page that was never ingested', () => {
    const policy = policyWith(stated('80%', 'reimbursed at 80%', 99));
    const violations = verifyPolicyCitations(policy, pages);
    expect(violations[0]?.kind).toBe('missing_page');
  });

  it('tolerates line breaks and curly quotes introduced by PDF text layers', () => {
    const policy = policyWith(
      stated('80%', 'reimbursed at 80%   of the\n\trecognised   tariff'),
    );
    expect(verifyPolicyCitations(policy, pages)).toEqual([]);
  });

  it('matches amounts across differing thousands separators', () => {
    const policy = policyWith(stated('15000', 'annual limit of 15,000 per insured member'));
    expect(verifyPolicyCitations(policy, pages)).toEqual([]);
  });

  it('requires no citation when the document is silent', () => {
    expect(verifyPolicyCitations(policyWith(notStated), pages)).toEqual([]);
  });
});

describe('numeric support', () => {
  const numericPages: PageIndex = new Map([
    [
      DOC,
      new Map([
        // Carries the insurer name too, since every fixture policy cites it here.
        [1, 'Example Assurance. Annual ceiling of 1.500 applies to physiotherapy.'],
        [2, 'Claims must be submitted within 30. Late claims are refused.'],
        [3, 'The excess is 1,500.50 per event.'],
      ]),
    ],
  ]);

  it('refuses to read a period-grouped figure as a thousands separator', () => {
    // "1.500" is 1500 under one convention and 1.5 under another. Treating them
    // as equal would let a claimed 1500 be justified by a quote saying 1.5.
    const policy = policyWith(stated('1500', 'ceiling of 1.500 applies', 1));
    const violations = verifyPolicyCitations(policy, numericPages);
    expect(violations.map((v) => v.kind)).toContain('value_not_in_quote');
  });

  it('accepts a period-grouped figure quoted exactly as printed', () => {
    const policy = policyWith(stated('1.500', 'ceiling of 1.500 applies', 1));
    expect(verifyPolicyCitations(policy, numericPages)).toEqual([]);
  });

  it('treats a comma before a decimal point as grouping', () => {
    const policy = policyWith(stated('1500.50', 'The excess is 1,500.50 per event.', 3));
    expect(verifyPolicyCitations(policy, numericPages)).toEqual([]);
  });

  it('does not manufacture a violation from sentence punctuation', () => {
    const policy = policyWith(stated('30', 'submitted within 30.', 2));
    expect(verifyPolicyCitations(policy, numericPages)).toEqual([]);
  });

  it('holds the normalized amount to the same proof as the displayed value', () => {
    const field: PolicyField = {
      status: 'stated',
      value: '80%',
      // Plausible on screen, wrong in the arithmetic that computes deadlines.
      normalized: { unit: 'days', amount: 8000, currency: null },
      source_citation: {
        document_id: DOC,
        page: 4,
        clause_ref: '4.2',
        verbatim_quote: 'reimbursed at 80% of the recognised tariff',
      },
      extraction_confidence: 'high',
    };
    const violations = verifyPolicyCitations(policyWith(field), pages);
    expect(violations.map((v) => v.kind)).toContain('value_not_in_quote');
    expect(violations[0]?.detail).toMatch(/normalized/);
  });

  it('checks figures inside an exclusion, not only structured fields', () => {
    const policy = policyWith(notStated);
    policy.coverage_items[0]!.exclusions = [
      {
        text: 'Physiotherapy above 9,999 per year is excluded.',
        source_citation: {
          document_id: DOC,
          page: 1,
          clause_ref: null,
          verbatim_quote: 'Annual ceiling of 1.500 applies to physiotherapy.',
        },
      },
    ];
    const violations = verifyPolicyCitations(policy, numericPages);
    expect(violations.map((v) => v.kind)).toContain('value_not_in_quote');
  });

  it('checks a deadline asserted in a claim step', () => {
    const policy = policyWith(notStated);
    policy.claims_process.steps = [
      {
        order: 1,
        instruction: 'Submit the receipt within 14 days.',
        source_citation: {
          document_id: DOC,
          page: 2,
          clause_ref: null,
          verbatim_quote: 'Claims must be submitted within 30.',
        },
      },
    ];
    const violations = verifyPolicyCitations(policy, numericPages);
    expect(violations.map((v) => v.kind)).toContain('value_not_in_quote');
  });

  it('checks each competing reading of ambiguous wording', () => {
    const ambiguous: PolicyField = {
      status: 'ambiguous',
      competing_readings: ['1.500 per year', '9,999 per year'],
      source_citation: {
        document_id: DOC,
        page: 1,
        clause_ref: null,
        verbatim_quote: 'Annual ceiling of 1.500 applies to physiotherapy.',
      },
      note: null,
    };
    const violations = verifyPolicyCitations(policyWith(ambiguous), numericPages);
    expect(violations).toHaveLength(1);
    expect(violations[0]?.detail).toMatch(/reading 2/);
  });
});

describe('schema shape', () => {
  it('refuses a stated figure that carries no source citation', () => {
    const uncited = {
      status: 'stated',
      value: '80%',
      normalized: null,
      extraction_confidence: 'high',
    };
    const result = extractedPolicySchema.safeParse(policyWith(uncited as unknown as PolicyField));
    expect(result.success).toBe(false);
  });

  it('offers no field in which to record a preferred reading of ambiguous text', () => {
    const ambiguous: PolicyField = {
      status: 'ambiguous',
      competing_readings: ['80% of tariff', '80% of invoice'],
      source_citation: { document_id: DOC, page: 4, clause_ref: '4.2', verbatim_quote: 'at 80%' },
      note: null,
    };
    const parsed = extractedPolicySchema.parse(policyWith(ambiguous));
    const field = parsed.coverage_items[0]?.coverage_percentage_or_amount;
    expect(field?.status).toBe('ambiguous');
    expect(field).not.toHaveProperty('value');
  });
});
