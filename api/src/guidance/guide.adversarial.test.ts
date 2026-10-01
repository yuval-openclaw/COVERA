// Through buildGuidance itself, with the model and the database replaced by
// synthetic stand-ins: a model that invents figures and a phone number, and a
// user with no evidence and no contacts on file.
import { describe, expect, it, vi } from 'vitest';

const contacts = vi.hoisted(() => ({ list: [] as { policyId: string; insurer: string | null; phone: string | null }[] }));

const invented = {
  clarifying_questions: [
    { question: 'Is the 999-day waiting period waived?', why: 'Your policy reimburses 98%.' },
    { question: 'Is the surgeon in your network?', why: 'Network surgeons are treated differently.' },
  ],
  relevant_policy_ids: [],
  summary: 'Follow the steps below.',
  steps: [
    { order: 1, action: 'You will be reimbursed 99%.', deadline_note: null,
      basis: { kind: 'cited', citation: { document_id: '3f1c2a9e-5b7d-4e21-9c3a-8d6f0b1e2a47', page: 1,
        clause_ref: null, verbatim_quote: 'Nothing like that is printed here.' } } },
    { order: 2, action: 'Ask whether a referral is needed.', deadline_note: null,
      basis: { kind: 'not_stated', ask_insurer: 'Do I need a referral?', insurer_phone: '+1 555 0100' } },
  ],
  conflicts: [],
  phone_script: null,
  draft_claim_email: null,
};

vi.mock('../ai/gemini.js', () => ({
  generateJson: vi.fn(async () => ({ raw: JSON.stringify(invented), value: structuredClone(invented) })),
  jsonSchemaFor: () => ({}),
  MODELS: { guidance: 'synthetic' },
  modelTurn: (raw: string) => ({ role: 'model', parts: [{ text: raw }] }),
  textPart: (text: string) => ({ text }),
  userTurn: (...parts: unknown[]) => ({ role: 'user', parts }),
}));

vi.mock('./retrieve.js', () => ({
  retrieveSnippets: async () => [],
  insurerContacts: async () => contacts.list,
  loadPagesForUser: async () => new Map(),
}));

const { buildGuidance } = await import('./guide.js');

describe('buildGuidance with an adversarial model', () => {
  it('lets no unsupported figure or invented phone number reach the response', async () => {
    contacts.list = [];
    const result = await buildGuidance({ userId: 'u-synthetic', situation: 'Planned knee surgery.' });
    const serialized = JSON.stringify(result);

    for (const figure of ['999', '98%', '99%', '555']) expect(serialized).not.toContain(figure);
    expect(result.plan.clarifying_questions.map((q) => q.question)).toEqual(['Is the surgeon in your network?']);
    const notStated = result.plan.steps.find((s) => s.basis.kind === 'not_stated');
    expect(notStated?.basis).toMatchObject({ insurer_phone: null });
  });

  it('keeps a phone number only when it is the one the policy states, in the policy’s own form', async () => {
    contacts.list = [{ policyId: 'p-synthetic', insurer: 'Synthetic Health', phone: '+1-555-0100' }];
    const result = await buildGuidance({ userId: 'u-synthetic', situation: 'Planned knee surgery.' });
    const notStated = result.plan.steps.find((s) => s.basis.kind === 'not_stated');
    expect(notStated?.basis).toMatchObject({ insurer_phone: '+1-555-0100' });
  });
});
