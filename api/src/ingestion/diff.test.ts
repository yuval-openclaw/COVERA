import { describe, expect, it } from 'vitest';
import type { CoverageItem, ExtractedPolicy, PolicyField } from '../schema/policy.js';
import { diffPolicies } from './diff.js';

const DOC = '11111111-1111-4111-8111-111111111111';

function stated(value: string): PolicyField {
  return {
    status: 'stated',
    value,
    normalized: null,
    source_citation: { document_id: DOC, page: 1, clause_ref: null, verbatim_quote: value },
    extraction_confidence: 'high',
  };
}

const notStated: PolicyField = { status: 'not_stated', note: null };

function coverage(category: string, overrides: Partial<CoverageItem> = {}): CoverageItem {
  return {
    category,
    coverage_percentage_or_amount: notStated,
    annual_limit: notStated,
    per_event_limit: notStated,
    deductible_or_copay: notStated,
    waiting_period_days: notStated,
    requires_preauthorization: notStated,
    network_restriction: notStated,
    exclusions: [],
    ...overrides,
  };
}

function policy(items: CoverageItem[], overrides: Partial<ExtractedPolicy> = {}): ExtractedPolicy {
  return {
    policy_id: '22222222-2222-4222-8222-222222222222',
    insurer_name: stated('Example Assurance'),
    policy_type: 'private_health',
    policy_number: stated('ABC-123'),
    insured_members: [],
    effective_date: notStated,
    renewal_date: notStated,
    coverage_items: items,
    claims_process: {
      steps: [],
      required_documents: [],
      submission_deadline_days: notStated,
      contact: { phone: notStated, email: notStated, portal_url: notStated },
    },
    ...overrides,
  };
}

describe('renewal diffing', () => {
  it('reports a changed figure with both sides intact', () => {
    const changes = diffPolicies(
      policy([coverage('surgery', { coverage_percentage_or_amount: stated('80%') })]),
      policy([coverage('surgery', { coverage_percentage_or_amount: stated('70%') })]),
    );

    expect(changes).toHaveLength(1);
    expect(changes[0]?.kind).toBe('value_changed');
    expect(changes[0]?.before).toMatchObject({ value: '80%' });
    expect(changes[0]?.after).toMatchObject({ value: '70%' });
  });

  it('distinguishes a newly silent field from an unchanged one', () => {
    const changes = diffPolicies(
      policy([coverage('surgery', { annual_limit: stated('15,000') })]),
      policy([coverage('surgery')]),
    );

    expect(changes[0]?.kind).toBe('became_unstated');
    expect(changes[0]?.summary).toMatch(/not necessarily unchanged/i);
  });

  it('does not treat a removed coverage category as settled', () => {
    const changes = diffPolicies(policy([coverage('dental')]), policy([]));

    expect(changes[0]?.kind).toBe('coverage_removed');
    expect(changes[0]?.summary).toMatch(/confirm with the insurer/i);
  });

  it('flags wording that has become ambiguous rather than picking a reading', () => {
    const ambiguous: PolicyField = {
      status: 'ambiguous',
      competing_readings: ['80% of tariff', '80% of invoice'],
      source_citation: { document_id: DOC, page: 2, clause_ref: null, verbatim_quote: 'at 80%' },
      note: null,
    };

    const changes = diffPolicies(
      policy([coverage('surgery', { coverage_percentage_or_amount: stated('80% of tariff') })]),
      policy([coverage('surgery', { coverage_percentage_or_amount: ambiguous })]),
    );

    expect(changes[0]?.kind).toBe('became_ambiguous');
    expect(changes[0]?.summary).toContain('80% of invoice');
  });

  it('reports nothing when the renewal restates identical terms', () => {
    const items = [coverage('surgery', { coverage_percentage_or_amount: stated('80%') })];
    expect(diffPolicies(policy(items), policy(items))).toEqual([]);
  });

  it('matches coverage categories regardless of casing or padding', () => {
    const changes = diffPolicies(
      policy([coverage('Surgery ', { annual_limit: stated('15,000') })]),
      policy([coverage('surgery', { annual_limit: stated('15,000') })]),
    );
    expect(changes).toEqual([]);
  });

  it('surfaces a shortened claim submission window', () => {
    const before = policy([]);
    const after = policy([], {
      claims_process: {
        ...policy([]).claims_process,
        submission_deadline_days: stated('30 days'),
      },
    });

    const changes = diffPolicies(before, after);
    expect(changes.map((c) => c.path)).toContain('claims_process.submission_deadline_days');
    expect(changes[0]?.kind).toBe('newly_stated');
  });
});
