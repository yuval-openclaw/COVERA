import { describe, expect, it } from 'vitest';
import type { ExtractedPolicy, PolicyField } from '../schema/policy.js';
import { downgradeUnproven, usesUnverified, withoutUnverified } from './unverified.js';
import { verifyPolicyCitations, type PageIndex } from './verify.js';

const DOC = '11111111-1111-4111-8111-111111111111';

const pages: PageIndex = new Map([
  [
    DOC,
    new Map([
      [1, 'Example Assurance — Policy Schedule\nPolicy number 55012345'],
      [4, 'Surgery is reimbursed at 80% of the recognised tariff, up to an annual limit of 15,000 per insured member.'],
    ]),
  ],
]);

function stated(value: string, quote: string, page: number): PolicyField {
  return {
    status: 'stated',
    value,
    normalized: null,
    source_citation: { document_id: DOC, page, clause_ref: null, verbatim_quote: quote },
    extraction_confidence: 'high',
  };
}

const notStated: PolicyField = { status: 'not_stated', note: null };

function policy(overrides: Partial<ExtractedPolicy> = {}): ExtractedPolicy {
  return {
    policy_id: '22222222-2222-4222-8222-222222222222',
    insurer_name: stated('Example Assurance', 'Example Assurance', 1),
    policy_type: 'private_health',
    // The extractor misread one digit: the page says 55012345.
    policy_number: stated('555012345', 'Policy number 555012345', 1),
    insured_members: [],
    effective_date: notStated,
    renewal_date: notStated,
    coverage_items: [
      {
        category: 'surgery',
        coverage_percentage_or_amount: stated('80%', 'reimbursed at 80% of the recognised tariff', 4),
        annual_limit: stated('15,000', 'up to an annual limit of 15,000 per insured member', 4),
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
    ...overrides,
  };
}

describe('keeping a policy when a single field is misread', () => {
  it('marks only the misread field unverified, with no figure, and keeps the rest', () => {
    const candidate = policy();
    const violations = verifyPolicyCitations(candidate, pages);
    expect(violations).toHaveLength(1);

    const kept = downgradeUnproven(candidate, violations, pages);
    expect(kept).not.toBeNull();
    expect(kept!.labels).toEqual(['policy_number']);
    expect(kept!.policy.policy_number.status).toBe('unverified');
    expect(JSON.stringify(kept!.policy.policy_number)).not.toContain('555012345');
    // Proven fields are untouched.
    expect(kept!.policy.coverage_items[0]!.annual_limit.status).toBe('stated');
    expect(verifyPolicyCitations(kept!.policy, pages)).toEqual([]);
  });

  it('refuses the whole document when an exclusion is unproven, because a missing exclusion reads as cover', () => {
    const candidate = policy({ policy_number: notStated });
    candidate.coverage_items[0]!.exclusions = [
      {
        text: 'Cosmetic surgery is excluded',
        source_citation: { document_id: DOC, page: 4, clause_ref: null, verbatim_quote: 'Cosmetic surgery is excluded' },
      },
    ];
    const violations = verifyPolicyCitations(candidate, pages);
    expect(violations).toHaveLength(1);
    expect(downgradeUnproven(candidate, violations, pages)).toBeNull();
  });

  it('refuses the whole document when too many fields are unproven', () => {
    const candidate = policy();
    const item = candidate.coverage_items[0]!;
    item.coverage_percentage_or_amount = stated('90%', 'reimbursed at 90%', 4);
    item.annual_limit = stated('20,000', 'annual limit of 20,000', 4);
    candidate.insurer_name = stated('Other Insurer', 'Other Insurer', 1);
    const violations = verifyPolicyCitations(candidate, pages);
    expect(violations.length).toBeGreaterThan(2);
    expect(downgradeUnproven(candidate, violations, pages)).toBeNull();
  });
});

describe('the extractor never sets "unverified" itself', () => {
  it('detects it anywhere in the output', () => {
    const candidate = policy({ renewal_date: { status: 'unverified', note: 'x' } });
    expect(usesUnverified(candidate)).toBe(true);
    expect(usesUnverified(policy())).toBe(false);
  });

  it('removes it from the structure the model is shown', () => {
    const schema = {
      anyOf: [
        { type: 'object', properties: { status: { const: 'stated' } } },
        { type: 'object', properties: { status: { enum: ['unverified'] } } },
      ],
    };
    expect(withoutUnverified(schema).anyOf).toHaveLength(1);
    expect(JSON.stringify(withoutUnverified(schema))).not.toContain('unverified');
  });
});
