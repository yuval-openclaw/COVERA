import type { PolicyField } from '../schema/policy.js';

/**
 * Only an unambiguous ISO date is stored. `new Date()` would read "03/04/2026"
 * as March 4th regardless of the document's convention, and "5" as a date in
 * 2001 — silently producing a renewal deadline nobody wrote down. When the
 * format is not certain the column stays null and the cited text remains the
 * only source of truth.
 */
const ISO_DATE = /^(\d{4})-(\d{2})-(\d{2})$/;

export function dateOf(field: PolicyField): string | null {
  if (field.status !== 'stated') return null;

  const match = ISO_DATE.exec(field.value.trim());
  if (!match) return null;

  const [, year, month, day] = match;
  const parsed = new Date(`${year}-${month}-${day}T00:00:00Z`);
  if (Number.isNaN(parsed.getTime())) return null;

  // Rejects overflow like 2026-02-31, which Date would roll forward silently.
  return parsed.toISOString().slice(0, 10) === `${year}-${month}-${day}`
    ? `${year}-${month}-${day}`
    : null;
}
