import { collectCitations, extractedPolicySchema, type ExtractedPolicy } from '../schema/policy.js';
import { verifyPolicyCitations, type CitationViolation, type PageIndex } from './verify.js';

/**
 * The "unverified" field state: how one misread field is kept out of a policy
 * without throwing the whole policy away. See the schema's unverifiedSchema.
 */

/** At most this share of cited fields may be unverified before the whole document is refused. */
const MAX_UNVERIFIED_SHARE = 0.25;
const UNVERIFIED_NOTE =
  'Covera read something here but could not match it exactly to the page, so no figure is shown. Check your policy document or ask your insurer.';

export function downgradeUnproven(
  policy: ExtractedPolicy,
  violations: CitationViolation[],
  pageIndex: PageIndex,
): { policy: ExtractedPolicy; labels: string[] } | null {
  if (violations.length === 0) return null;
  // A list entry (exclusion, claim step, required document) cannot be dropped
  // safely: a missing exclusion reads as cover.
  if (violations.some((v) => !v.target)) return null;

  const targets = new Map<string, NonNullable<CitationViolation['target']>>();
  for (const v of violations) targets.set(v.target!.label.replace(/ \(normalized\)$| reading \d+$/, ''), v.target!);

  const citedFields = collectCitations(policy).length;
  if (targets.size > Math.max(2, Math.floor(citedFields * MAX_UNVERIFIED_SHARE))) return null;

  for (const target of targets.values()) {
    target.owner[target.key] = { status: 'unverified', note: UNVERIFIED_NOTE };
  }

  // The result must now verify cleanly and still match the schema; if not,
  // something else is wrong and the document is refused.
  const reparsed = extractedPolicySchema.safeParse(policy);
  if (!reparsed.success || verifyPolicyCitations(reparsed.data, pageIndex).length > 0) return null;
  return { policy: reparsed.data, labels: [...targets.keys()] };
}

export function usesUnverified(node: unknown): boolean {
  if (Array.isArray(node)) return node.some(usesUnverified);
  if (node === null || typeof node !== 'object') return false;
  const record = node as Record<string, unknown>;
  if (record['status'] === 'unverified') return true;
  return Object.values(record).some(usesUnverified);
}

/** Removes the unverified branch from every union in a JSON schema. */
export function withoutUnverified<T>(schema: T): T {
  const strip = (node: unknown): unknown => {
    if (Array.isArray(node)) return node.map(strip);
    if (node === null || typeof node !== 'object') return node;
    const out: Record<string, unknown> = {};
    for (const [key, value] of Object.entries(node as Record<string, unknown>)) {
      if ((key === 'anyOf' || key === 'oneOf') && Array.isArray(value)) {
        out[key] = value.filter((branch) => !isUnverifiedBranch(branch)).map(strip);
      } else {
        out[key] = strip(value);
      }
    }
    return out;
  };
  return strip(schema) as T;
}

function isUnverifiedBranch(branch: unknown): boolean {
  const status = (branch as { properties?: { status?: { enum?: unknown[]; const?: unknown } } })
    ?.properties?.status;
  return status?.const === 'unverified' || (Array.isArray(status?.enum) && status.enum.includes('unverified'));
}
