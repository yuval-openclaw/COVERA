import {
  generateJson,
  jsonSchemaFor,
  MODELS,
  modelTurn,
  textPart,
  userTurn,
  type Content,
} from '../ai/gemini.js';
import { guidancePlanSchema, type ActionStep, type GuidancePlan } from './schema.js';
import {
  supportedNumbers,
  unsupportedFiguresIn,
  verifySteps,
  type StepFailure,
} from './verify-steps.js';
import {
  insurerContacts,
  loadPagesForUser,
  retrieveSnippets,
  type RetrievedSnippet,
} from './retrieve.js';

const SYSTEM_PROMPT = `You help someone act during a medical event, using only their own insurance documents. You are reading their policies back to them, not advising them.

Rules, in order of precedence:

1. Every figure — percentage, sum, cap, waiting period, deadline — must come from a snippet you were given, and the step asserting it must carry basis.kind "cited" with a verbatim_quote copied character-for-character from that snippet. If no snippet supports it, you may not state it.
2. When the documents do not answer something that matters, say so plainly and use basis.kind "not_stated" with the question the user should ask their insurer. This is a good answer, not a failure. Never fill the gap with how insurance usually works. Ask the question open ("is there a waiting period for this surgery?"), never with a figure in it ("is the 90-day wait waived?") — a number inside a question is still a number you invented.
3. basis.kind "general" is only for procedural steps that assert nothing about this person's coverage ("bring photo ID", "keep the original receipt"). Never use it to smuggle in a figure.
4. Where two policies overlap or conflict, list both in conflicts with their citations. Do not pick the more favourable one.
5. Never predict an outcome. You do not know what will be approved. Describe what the documents say and what to do next.
6. Never give medical advice, never suggest a diagnosis or treatment, never tell someone whether to have a procedure.
7. Ask clarifying questions only when the answer would genuinely change the plan — which family member, how urgent, whether a referral already exists. Keep them short; the reader is frightened and short on attention.
8. The phone script and the draft claim email obey rule 1 too: they may repeat only figures that appear in a cited step's quote. For anything the user must fill in — an amount, a date, a policy number — write a bracketed placeholder such as [amount] or [policy number], never a guess.

Tone: calm, numbered, concrete. Short sentences. No reassurance you cannot back up, no congratulation, no exclamation marks.`;

export interface GuidanceResult {
  plan: GuidancePlan;
  /** Steps removed because their citation could not be verified. */
  withheld: string[];
  usedOcrPages: boolean;
}

export async function buildGuidance(params: {
  userId: string;
  situation: string;
  answers?: Record<string, string>;
  locale?: string;
}): Promise<GuidanceResult> {
  const { userId, situation, answers, locale = 'en' } = params;

  const snippets = await retrieveSnippets(userId, situation);
  const contacts = await insurerContacts(userId);

  const evidence = `Snippets from this user's active policies. These are the only evidence you may cite.\n\n${formatSnippets(
    snippets,
  )}\n\nInsurer contacts on file:\n${contacts
    .map((c) => `- ${c.insurer ?? 'Unnamed insurer'} (policy ${c.policyId}): ${c.phone ?? 'no phone recorded'}`)
    .join('\n')}`;

  const given =
    answers && Object.keys(answers).length > 0
      ? `\n\nAnswers already given:\n${Object.entries(answers)
          .map(([q, a]) => `- ${q}: ${a}`)
          .join('\n')}`
      : '';

  const contents: Content[] = [
    userTurn(
      textPart(evidence),
      textPart(
        `Write the plan in language: ${locale.slice(0, 2)}. Verbatim quotes stay in the document's own language.\n\nSituation: ${situation}${given}`,
      ),
    ),
  ];
  const schema = jsonSchemaFor(guidancePlanSchema);

  const documentIds = [...new Set(snippets.map((s) => s.documentId))];
  const pages = await loadPagesForUser(userId, documentIds);

  let plan: GuidancePlan | null = null;
  let unverified: StepFailure[] = [];
  let proseProblems: string[] = [];

  // Same contract as extraction: the verifier is the feedback signal, and a
  // claim that cannot be traced does not reach the user.
  for (let attempt = 1; attempt <= 2; attempt++) {
    const { raw, value } = await generateJson({
      model: MODELS.guidance,
      system: SYSTEM_PROMPT,
      contents,
      schema,
    });

    const parsed = guidancePlanSchema.safeParse(value);
    if (!parsed.success) {
      contents.push(
        modelTurn(raw),
        userTurn(
          textPart(
            `Rejected: ${parsed.error.issues
              .map((i) => `${i.path.join('.')}: ${i.message}`)
              .join('; ')}. Return the corrected plan as JSON.`,
          ),
        ),
      );
      continue;
    }

    plan = parsed.data;
    unverified = verifySteps(plan.steps, pages);
    proseProblems = narrativeProblems(plan, unverified);
    if (unverified.length === 0 && proseProblems.length === 0) break;

    const complaints = [
      ...unverified.map((u) => `- step ${u.step.order}: ${u.reason}`),
      ...proseProblems.map((p) => `- ${p}`),
    ];

    contents.push(
      modelTurn(raw),
      userTurn(
        textPart(
          `These parts of the plan assert something the documents do not support:\n${complaints.join(
            '\n',
          )}\nQuote exactly what is printed, or change the step to basis "not_stated" and tell the user to ask their insurer. Any figure in the summary, a conflict, the phone script or the claim email must also appear in a step's quote. Return the corrected plan as JSON.`,
        ),
      ),
    );
  }

  if (!plan) throw new Error('Guidance could not produce a valid plan');

  // Anything still unverified after the repair attempt is withheld rather than
  // shown with a caveat — a wrong figure mid-crisis is worse than a gap.
  const withheldOrders = new Set(unverified.map((u) => u.step.order));
  const safeSteps = plan.steps.filter((s) => !withheldOrders.has(s.order));

  // Prose is checked against the steps that survived, not the steps that were
  // asked for: withholding a step must also retract any figure the summary drew
  // from it.
  const supported = supportedNumbers(plan.steps, unverified);
  const withheld = unverified.map(
    (u) => `A step about "${truncate(u.step.action)}" was withheld: ${u.reason}`,
  );

  let summary = plan.summary;
  if (unsupportedFiguresIn(summary, supported).length > 0) {
    summary =
      'The summary was withheld because it stated a figure that could not be traced to your documents. The numbered steps below are the part that checked out.';
    withheld.push('The summary was withheld: it stated a figure no quote supports.');
  }

  const safeConflicts = plan.conflicts.filter((conflict) => {
    if (unsupportedFiguresIn(conflict, supported).length === 0) return true;
    withheld.push('A note about conflicting policies was withheld: it stated an unsupported figure.');
    return false;
  });

  // The script is read aloud to the insurer and the email is sent to them, so
  // an invented figure in either goes straight to the one party who will hold
  // the user to it. Dropped whole rather than edited: a half-redacted email is
  // worse than none.
  let phoneScript = plan.phone_script;
  if (phoneScript && unsupportedFiguresIn(phoneScript, supported).length > 0) {
    phoneScript = null;
    withheld.push('The phone script was withheld: it stated a figure no quote supports.');
  }

  let draftEmail = plan.draft_claim_email;
  if (draftEmail && unsupportedFiguresIn(draftEmail, supported).length > 0) {
    draftEmail = null;
    withheld.push('The draft claim email was withheld: it stated a figure no quote supports.');
  }

  return {
    plan: {
      ...plan,
      summary,
      steps: renumber(safeSteps),
      conflicts: safeConflicts,
      phone_script: phoneScript,
      draft_claim_email: draftEmail,
    },
    withheld,
    usedOcrPages: snippets.some((s) => s.ocr),
  };
}

/** Figures asserted in prose that no surviving citation supports. */
function narrativeProblems(plan: GuidancePlan, failed: StepFailure[]): string[] {
  const supported = supportedNumbers(plan.steps, failed);
  const problems: string[] = [];

  const summaryFigures = unsupportedFiguresIn(plan.summary, supported);
  if (summaryFigures.length > 0) {
    problems.push(
      `the summary states ${summaryFigures.join(', ')}, which no step's quote contains`,
    );
  }

  for (const conflict of plan.conflicts) {
    const figures = unsupportedFiguresIn(conflict, supported);
    if (figures.length > 0) {
      problems.push(`a conflict note states ${figures.join(', ')} without a quote behind it`);
    }
  }

  for (const [label, text] of [
    ['the phone script', plan.phone_script],
    ['the draft claim email', plan.draft_claim_email],
  ] as const) {
    const figures = text ? unsupportedFiguresIn(text, supported) : [];
    if (figures.length > 0) {
      problems.push(
        `${label} states ${figures.join(', ')}, which no step's quote contains — use a [placeholder] instead`,
      );
    }
  }
  return problems;
}


function renumber(steps: ActionStep[]): ActionStep[] {
  return steps
    .slice()
    .sort((a, b) => a.order - b.order)
    .map((step, i) => ({ ...step, order: i + 1 }));
}

function formatSnippets(snippets: RetrievedSnippet[]): string {
  if (snippets.length === 0) return '(No policy text matched this situation.)';
  return snippets
    .map(
      (s) =>
        `[document_id: ${s.documentId} | page: ${s.page}${s.ocr ? ' | scanned page, transcribed' : ''}]\n${s.text}`,
    )
    .join('\n\n---\n\n');
}

function truncate(text: string): string {
  return text.length > 80 ? `${text.slice(0, 77)}...` : text;
}
