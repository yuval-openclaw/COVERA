import type {
  ExtractedPolicy,
  PolicyField,
  SourceCitation,
} from '../schema/policy.js';

/**
 * Schema validation proves a figure claims a source. This proves the source
 * says what the figure claims. Both run before extraction output is persisted.
 */

export interface CitationViolation {
  kind: 'missing_page' | 'quote_not_found' | 'value_not_in_quote';
  document_id: string;
  page: number;
  detail: string;
}

/** Page text keyed by document id, then 1-based page number. */
export type PageIndex = Map<string, Map<number, string>>;

/**
 * PDF text layers vary in spacing, ligatures and quote styling between
 * extractors, so comparison happens on a flattened form. Digits and letters are
 * preserved exactly; only presentation is normalized.
 */
export function normalize(text: string): string {
  return text
    .normalize('NFKC')
    // Hebrew and Arabic text layers carry invisible direction marks and
    // zero-width joiners that differ between the PDF and any quote of it.
    // They render as nothing and hold no content, so a quote that matches
    // apart from them is still a character-for-character match.
    .replace(/[​-‏‪-‮⁦-⁩؜﻿]/g, '')
    .replace(/[‘’‛′]/g, "'")
    .replace(/[“”‟″]/g, '"')
    .replace(/[‐-―−]/g, '-')
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase();
}

const NUMERIC_TOKEN = /\d[\d.,]*/g;

/**
 * Digit grouping is not normalized away, because doing so cannot be undone
 * safely: "1.500" is fifteen hundred under one convention and one-and-a-half
 * under another. Stripping the separator would let a European-formatted 1.5
 * verify a claimed 1500 — a thousandfold error in a figure someone is about to
 * spend money against.
 *
 * Commas are only removed where they are unambiguously grouping separators.
 * A lone period is always left intact, so a mismatch is reported and the
 * extractor is asked to quote the figure precisely instead.
 */
function canonicalNumber(token: string): string {
  const trimmed = token.replace(/[.,]+$/, '');
  // With both present the comma groups and the period is the decimal point,
  // so trailing decimal zeros can be dropped: 1,196,454.00 is 1196454 exactly.
  if (trimmed.includes(',') && trimmed.includes('.')) {
    return trimmed.replace(/,/g, '').replace(/\.0+$/, '');
  }
  if (trimmed.includes(',')) return trimmed.replace(/,(?=\d{3}\b)/g, '');
  return trimmed;
}

export function numbersIn(text: string): string[] {
  return (text.match(NUMERIC_TOKEN) ?? []).map(canonicalNumber).filter((t) => t.length > 0);
}

interface CitedText {
  /** Text whose figures must be supported by the citation's own quote. */
  text: string;
  citation: SourceCitation;
  label: string;
}

export function verifyPolicyCitations(
  policy: ExtractedPolicy,
  pages: PageIndex,
): CitationViolation[] {
  const violations: CitationViolation[] = [];
  const cited = collectCitedText(policy);

  for (const { text, citation, label } of cited) {
    const pageText = pages.get(citation.document_id)?.get(citation.page);

    if (pageText === undefined) {
      violations.push({
        kind: 'missing_page',
        document_id: citation.document_id,
        page: citation.page,
        detail: `${label} cites page ${citation.page} of ${citation.document_id}, which was not ingested.`,
      });
      continue;
    }

    if (!normalize(pageText).includes(normalize(citation.verbatim_quote))) {
      violations.push({
        kind: 'quote_not_found',
        document_id: citation.document_id,
        page: citation.page,
        detail: `${label}: quoted text does not appear on the cited page: "${citation.verbatim_quote}"`,
      });
      continue;
    }

    const supported = new Set(numbersIn(citation.verbatim_quote));
    const unsupported = numbersIn(text).filter((n) => !supported.has(n));

    if (unsupported.length > 0) {
      violations.push({
        kind: 'value_not_in_quote',
        document_id: citation.document_id,
        page: citation.page,
        detail: `${label}: "${text}" contains ${unsupported.join(', ')}, which the supporting quote does not contain. Quote the figure exactly as printed, including how it is punctuated.`,
      });
    }
  }

  return violations;
}

/**
 * The policy shape is fixed, so it is walked explicitly. A generic traversal
 * silently skips anything it does not recognise, which is the wrong failure
 * direction: free text carrying an uncited cap or deadline would go unchecked.
 */
function collectCitedText(policy: ExtractedPolicy): CitedText[] {
  const out: CitedText[] = [];

  const field = (label: string, f: PolicyField): void => {
    if (f.status === 'stated') {
      out.push({ text: f.value, citation: f.source_citation, label });
      // The normalized amount drives deadline arithmetic, so it is held to the
      // same standard as the displayed value rather than trusted alongside it.
      if (f.normalized !== null) {
        out.push({
          text: String(f.normalized.amount),
          citation: f.source_citation,
          label: `${label} (normalized)`,
        });
      }
    } else if (f.status === 'ambiguous') {
      f.competing_readings.forEach((reading, i) => {
        out.push({ text: reading, citation: f.source_citation, label: `${label} reading ${i + 1}` });
      });
    }
  };

  field('insurer_name', policy.insurer_name);
  field('policy_number', policy.policy_number);
  field('effective_date', policy.effective_date);
  field('renewal_date', policy.renewal_date);

  policy.coverage_items.forEach((item, index) => {
    const at = `coverage_items[${index}] (${item.category})`;
    field(`${at}.coverage_percentage_or_amount`, item.coverage_percentage_or_amount);
    field(`${at}.annual_limit`, item.annual_limit);
    field(`${at}.per_event_limit`, item.per_event_limit);
    field(`${at}.deductible_or_copay`, item.deductible_or_copay);
    field(`${at}.waiting_period_days`, item.waiting_period_days);
    field(`${at}.requires_preauthorization`, item.requires_preauthorization);
    field(`${at}.network_restriction`, item.network_restriction);
    item.exclusions.forEach((exclusion, i) => {
      out.push({
        text: exclusion.text,
        citation: exclusion.source_citation,
        label: `${at}.exclusions[${i}]`,
      });
    });
  });

  const claims = policy.claims_process;
  field('claims_process.submission_deadline_days', claims.submission_deadline_days);
  field('claims_process.contact.phone', claims.contact.phone);
  field('claims_process.contact.email', claims.contact.email);
  field('claims_process.contact.portal_url', claims.contact.portal_url);

  claims.steps.forEach((step, i) => {
    out.push({
      text: step.instruction,
      citation: step.source_citation,
      label: `claims_process.steps[${i}]`,
    });
  });
  claims.required_documents.forEach((doc, i) => {
    out.push({
      text: doc.text,
      citation: doc.source_citation,
      label: `claims_process.required_documents[${i}]`,
    });
  });

  return out;
}
