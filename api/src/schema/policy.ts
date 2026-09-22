import { z } from 'zod';

/**
 * The citation principle is enforced by the type system, not by prompt wording.
 * There is no representation of a figure without its source, so an uncited
 * number cannot survive schema validation and therefore cannot reach the user.
 */

export const sourceCitationSchema = z.object({
  document_id: z.string().uuid(),
  page: z.number().int().positive(),
  clause_ref: z.string().nullable(),
  /** Copied character-for-character from the page so the claim can be machine-verified. */
  verbatim_quote: z.string().min(1),
});
export type SourceCitation = z.infer<typeof sourceCitationSchema>;

export const extractionConfidenceSchema = z.enum(['high', 'medium', 'low']);
export type ExtractionConfidence = z.infer<typeof extractionConfidenceSchema>;

export const normalizedValueSchema = z.object({
  unit: z.enum(['percent', 'currency', 'days', 'count']),
  amount: z.number(),
  currency: z.string().length(3).nullable(),
});

const statedSchema = z.object({
  status: z.literal('stated'),
  value: z.string().min(1),
  /** Machine-comparable form, used for deadline maths. Null when the text resists parsing. */
  normalized: normalizedValueSchema.nullable(),
  source_citation: sourceCitationSchema,
  extraction_confidence: extractionConfidenceSchema,
});

/** The document genuinely says nothing. Distinct from "we failed to find it". */
const notStatedSchema = z.object({
  status: z.literal('not_stated'),
  note: z.string().nullable(),
});

/**
 * The document addresses the point but supports more than one honest reading.
 * Competing readings are retained side by side; there is deliberately no field
 * in which to record a preferred one.
 */
const ambiguousSchema = z.object({
  status: z.literal('ambiguous'),
  competing_readings: z.array(z.string().min(1)).min(2),
  source_citation: sourceCitationSchema,
  note: z.string().nullable(),
});

/**
 * The document does address this, but the figure read from it could not be
 * proved against the page, so none is kept. Set only by Covera after the
 * extractor's last attempt, never by the extractor itself: it exists so that
 * one misread field does not throw away a whole policy, without pretending the
 * document is silent (that is not_stated) and without keeping an unproven
 * figure. Shown to the user as "check your policy or ask your insurer".
 */
const unverifiedSchema = z.object({
  status: z.literal('unverified'),
  note: z.string(),
});

export const policyFieldSchema = z.discriminatedUnion('status', [
  statedSchema,
  notStatedSchema,
  ambiguousSchema,
  unverifiedSchema,
]);
export type PolicyField = z.infer<typeof policyFieldSchema>;

export const policyTypeSchema = z.enum([
  'private_health',
  'supplementary_shaban',
  'critical_illness',
  'dental',
  'travel',
  'other',
]);

export const networkRestrictionSchema = z.enum(['in_network', 'out_of_network', 'any']);

export const exclusionSchema = z.object({
  text: z.string().min(1),
  source_citation: sourceCitationSchema,
});

export const coverageItemSchema = z.object({
  category: z.string().min(1),
  coverage_percentage_or_amount: policyFieldSchema,
  annual_limit: policyFieldSchema,
  per_event_limit: policyFieldSchema,
  deductible_or_copay: policyFieldSchema,
  waiting_period_days: policyFieldSchema,
  requires_preauthorization: policyFieldSchema,
  network_restriction: policyFieldSchema,
  exclusions: z.array(exclusionSchema),
});
export type CoverageItem = z.infer<typeof coverageItemSchema>;

export const claimStepSchema = z.object({
  order: z.number().int().positive(),
  instruction: z.string().min(1),
  source_citation: sourceCitationSchema,
});

export const insurerContactSchema = z.object({
  phone: policyFieldSchema,
  email: policyFieldSchema,
  portal_url: policyFieldSchema,
});

export const claimsProcessSchema = z.object({
  steps: z.array(claimStepSchema),
  required_documents: z.array(exclusionSchema),
  submission_deadline_days: policyFieldSchema,
  contact: insurerContactSchema,
});

export const extractedPolicySchema = z.object({
  policy_id: z.string().uuid(),
  insurer_name: policyFieldSchema,
  policy_type: policyTypeSchema,
  policy_number: policyFieldSchema,
  insured_members: z.array(z.string()),
  effective_date: policyFieldSchema,
  renewal_date: policyFieldSchema,
  coverage_items: z.array(coverageItemSchema),
  claims_process: claimsProcessSchema,
});
export type ExtractedPolicy = z.infer<typeof extractedPolicySchema>;

/** Every citation carried anywhere in a policy, for verification sweeps. */
export function collectCitations(policy: ExtractedPolicy): SourceCitation[] {
  const found: SourceCitation[] = [];

  const visit = (node: unknown): void => {
    if (Array.isArray(node)) {
      node.forEach(visit);
      return;
    }
    if (node === null || typeof node !== 'object') return;

    const record = node as Record<string, unknown>;
    const parsed = sourceCitationSchema.safeParse(record['source_citation']);
    if (parsed.success) found.push(parsed.data);

    Object.values(record).forEach(visit);
  };

  visit(policy);
  return found;
}
