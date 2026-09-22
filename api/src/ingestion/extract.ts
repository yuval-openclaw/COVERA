import {
  generateJson,
  jsonSchemaFor,
  MODELS,
  modelTurn,
  pdfPart,
  textPart,
  userTurn,
  type Content,
} from '../ai/gemini.js';
import {
  collectCitations,
  extractedPolicySchema,
  type ExtractedPolicy,
} from '../schema/policy.js';
import type { PageText } from './pdf.js';
import { verifyPolicyCitations, type CitationViolation, type PageIndex } from './verify.js';

/** The model never authors the policy's own id; it is assigned by the caller. */
const outputSchema = extractedPolicySchema.omit({ policy_id: true });

const SYSTEM_PROMPT = `You extract insurance policy terms into a fixed structure. You are not summarising and you are not advising; you are transcribing what a document states, with proof.

Rules, in order of precedence:

1. Every figure you record — percentage, amount, cap, waiting period, deadline — must use status "stated" and carry a source_citation whose verbatim_quote is copied character-for-character from the page you cite. Copy it; never retype from memory, never tidy the wording, never translate it.
1a. Copy the quote from the PAGE TEXT supplied below the document, not from the image of the page. The two can differ: in Hebrew and Arabic the stored text often runs in a different order from the printed line (a number can precede its label), and that stored order is what a quote is checked against. Copy the run of characters exactly as the page text has it, including its order and spacing. Never add brackets, ellipses or words of your own to a quote: if the wording you want is not in the page text, the field is not_stated.
2. If the document does not address a field, use status "not_stated". This is a correct and complete answer. Never infer a value from what this insurer usually offers, from another policy, or from how insurance normally works.
3. If the wording genuinely supports more than one reading, use status "ambiguous" and record each reading separately. Do not choose between them, and do not record the one you think is intended.
4. page is the physical page number the quote appears on, counting from 1.
5. extraction_confidence describes how legible the source is, not how confident you feel about the meaning. A blurred, rotated or handwritten page is "low" even when the reading seems obvious.
6. normalized is for machine comparison: a percentage becomes {unit:"percent",amount:80,currency:null}; a sum becomes {unit:"currency",amount:15000,currency:"ILS"}; a period becomes {unit:"days",amount:90,currency:null}. Set it to null when the text does not reduce cleanly to a number.

A user will act on this during a medical emergency. An omission is safe. An invented figure is not.`;

export interface ExtractionResult {
  policy: ExtractedPolicy;
  violations: CitationViolation[];
  attempts: number;
}

export async function extractPolicy(params: {
  policyId: string;
  documentId: string;
  pdf: Buffer;
  pages: PageText[];
}): Promise<ExtractionResult> {
  const { policyId, documentId, pdf, pages } = params;

  const pageIndex: PageIndex = new Map([
    [documentId, new Map(pages.map((p) => [p.page, p.text]))],
  ]);

  const schema = jsonSchemaFor(outputSchema);
  const contents: Content[] = [
    userTurn(
      pdfPart(pdf),
      // The same text the verifier checks quotes against, so a quote can be
      // copied from it rather than read off the rendered page.
      textPart(
        `PAGE TEXT (quote from this, exactly):\n${pages
          .map((p) => `--- page ${p.page} ---\n${p.text}`)
          .join('\n\n')}`,
      ),
      textPart(`Extract this policy. Use exactly "${documentId}" as document_id in every citation.`),
    ),
  ];

  // The verifier is the feedback signal: a failed check is returned to the model
  // as a correction rather than being papered over or silently accepted.
  const MAX_ATTEMPTS = 3;
  let lastViolations: CitationViolation[] = [];
  let lastSchemaIssues: string[] = [];

  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    const { raw, value } = await generateJson({
      model: MODELS.extraction,
      system: SYSTEM_PROMPT,
      contents,
      schema,
      maxOutputTokens: 32768,
      // The full policy schema is too large for Gemini to enforce while
      // decoding (it returns 400 "too many states"), so it is sent as
      // instructions; zod and the verifier below still decide what is accepted.
      constrain: false,
    });

    const parsed = extractedPolicySchema.safeParse({
      ...(typeof value === 'object' && value !== null ? value : {}),
      policy_id: policyId,
    });

    if (!parsed.success) {
      lastSchemaIssues = parsed.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`);
      contents.push(
        modelTurn(raw),
        userTurn(
          textPart(
            `The structure was rejected:\n${lastSchemaIssues
              .map((issue) => `- ${issue}`)
              .join('\n')}\nReturn the complete corrected JSON.`,
          ),
        ),
      );
      continue;
    }

    const foreign = collectCitations(parsed.data).filter((c) => c.document_id !== documentId);
    const violations = [
      ...verifyPolicyCitations(parsed.data, pageIndex),
      ...foreign.map(
        (c): CitationViolation => ({
          kind: 'missing_page',
          document_id: c.document_id,
          page: c.page,
          detail: `Citation references a document other than ${documentId}.`,
        }),
      ),
    ];

    if (violations.length === 0) {
      return { policy: parsed.data, violations: [], attempts: attempt };
    }

    lastViolations = violations;
    lastSchemaIssues = [];
    contents.push(
      modelTurn(raw),
      userTurn(
        textPart(
          `${violations.length} citation(s) could not be verified against the document:\n${violations
            .map((v) => `- p${v.page}: ${v.detail}`)
            .join(
              '\n',
            )}\nA quote must appear on the page you cite, character-for-character. If you cannot locate the exact wording, record that field as not_stated instead. Return the complete corrected JSON.`,
        ),
      ),
    );
  }

  throw new ExtractionFailedError(lastViolations, lastSchemaIssues);
}

export class ExtractionFailedError extends Error {
  constructor(
    readonly violations: CitationViolation[],
    readonly schemaIssues: string[] = [],
  ) {
    super(
      `Extraction did not produce a verifiable result after repeated attempts (${violations.length} unverified citation(s), ${schemaIssues.length} structural problem(s)).`,
    );
    this.name = 'ExtractionFailedError';
  }
}
