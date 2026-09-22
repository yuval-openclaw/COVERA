import { describe, expect, it } from 'vitest';
import type { PolicyField } from '../schema/policy.js';
import { dateOf } from './dates.js';

function stated(value: string): PolicyField {
  return {
    status: 'stated',
    value,
    normalized: null,
    source_citation: {
      document_id: '11111111-1111-4111-8111-111111111111',
      page: 1,
      clause_ref: null,
      verbatim_quote: value,
    },
    extraction_confidence: 'high',
  };
}

describe('policy date storage', () => {
  it('stores an unambiguous ISO date', () => {
    expect(dateOf(stated('2026-04-03'))).toBe('2026-04-03');
  });

  it('refuses a slash date whose day and month order is unknowable', () => {
    // Read as March 4th by Date(), but the document may well mean 3 April.
    expect(dateOf(stated('03/04/2026'))).toBeNull();
  });

  it('refuses a bare number that Date would silently turn into a date', () => {
    expect(dateOf(stated('5'))).toBeNull();
  });

  it('refuses a calendar date that does not exist', () => {
    expect(dateOf(stated('2026-02-31'))).toBeNull();
  });

  it('stores nothing when the document did not state a date', () => {
    expect(dateOf({ status: 'not_stated', note: null })).toBeNull();
  });
});
