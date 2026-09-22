import type { CoverageItem, ExtractedPolicy, PolicyField } from '../schema/policy.js';

/**
 * Renewal diffing. The transitions matter as much as the values: a policy that
 * previously stated a figure and is now silent has changed materially for the
 * user, even though no number moved. Those cases get their own kinds rather
 * than collapsing into "changed".
 */
export type ChangeKind =
  | 'value_changed'
  | 'became_unstated'
  | 'newly_stated'
  | 'became_ambiguous'
  | 'ambiguity_resolved'
  | 'coverage_added'
  | 'coverage_removed';

export interface FieldChange {
  path: string;
  kind: ChangeKind;
  before: PolicyField | null;
  after: PolicyField | null;
  /** Plain-language description; carries no figure that is not in before/after. */
  summary: string;
}

export function diffPolicies(before: ExtractedPolicy, after: ExtractedPolicy): FieldChange[] {
  const changes: FieldChange[] = [];

  const topLevel = ['insurer_name', 'policy_number', 'effective_date', 'renewal_date'] as const;
  for (const key of topLevel) {
    changes.push(...compareField(key, before[key], after[key]));
  }

  changes.push(
    ...compareField(
      'claims_process.submission_deadline_days',
      before.claims_process.submission_deadline_days,
      after.claims_process.submission_deadline_days,
    ),
  );

  changes.push(...diffCoverage(before.coverage_items, after.coverage_items));
  return changes;
}

function diffCoverage(before: CoverageItem[], after: CoverageItem[]): FieldChange[] {
  const changes: FieldChange[] = [];
  const key = (c: CoverageItem) => c.category.trim().toLowerCase();

  const beforeByCategory = new Map(before.map((c) => [key(c), c]));
  const afterByCategory = new Map(after.map((c) => [key(c), c]));

  for (const [category, item] of afterByCategory) {
    if (!beforeByCategory.has(category)) {
      changes.push({
        path: `coverage_items.${category}`,
        kind: 'coverage_added',
        before: null,
        after: item.coverage_percentage_or_amount,
        summary: `"${item.category}" appears in the new policy and was not in the previous one.`,
      });
    }
  }

  for (const [category, item] of beforeByCategory) {
    const next = afterByCategory.get(category);
    if (!next) {
      changes.push({
        path: `coverage_items.${category}`,
        kind: 'coverage_removed',
        before: item.coverage_percentage_or_amount,
        after: null,
        summary: `"${item.category}" was in the previous policy and does not appear in the new one. Confirm with the insurer before assuming it is gone.`,
      });
      continue;
    }

    const fields = [
      'coverage_percentage_or_amount',
      'annual_limit',
      'per_event_limit',
      'deductible_or_copay',
      'waiting_period_days',
      'requires_preauthorization',
      'network_restriction',
    ] as const;

    for (const field of fields) {
      changes.push(
        ...compareField(`coverage_items.${category}.${field}`, item[field], next[field]),
      );
    }
  }

  return changes;
}

function compareField(path: string, before: PolicyField, after: PolicyField): FieldChange[] {
  if (before.status === 'stated' && after.status === 'stated') {
    if (before.value.trim() === after.value.trim()) return [];
    return [
      {
        path,
        kind: 'value_changed',
        before,
        after,
        summary: `Changed from "${before.value}" to "${after.value}".`,
      },
    ];
  }

  if (before.status === 'stated' && after.status === 'not_stated') {
    return [
      {
        path,
        kind: 'became_unstated',
        before,
        after,
        summary: `The previous policy stated "${before.value}". The new document does not state this. It is not necessarily unchanged — confirm with the insurer.`,
      },
    ];
  }

  if (before.status === 'not_stated' && after.status === 'stated') {
    return [
      {
        path,
        kind: 'newly_stated',
        before,
        after,
        summary: `The new policy states "${after.value}", where the previous document was silent.`,
      },
    ];
  }

  if (before.status !== 'ambiguous' && after.status === 'ambiguous') {
    return [
      {
        path,
        kind: 'became_ambiguous',
        before,
        after,
        summary: `The new wording supports more than one reading: ${after.competing_readings
          .map((r) => `"${r}"`)
          .join(' or ')}. Ask the insurer which applies.`,
      },
    ];
  }

  if (before.status === 'ambiguous' && after.status === 'stated') {
    return [
      {
        path,
        kind: 'ambiguity_resolved',
        before,
        after,
        summary: `Previously ambiguous wording now states "${after.value}".`,
      },
    ];
  }

  return [];
}
