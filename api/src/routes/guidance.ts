import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { buildGuidance } from '../guidance/guide.js';
import { disclaimerFor } from '../guidance/schema.js';
import { allow, DAY } from '../auth/rate-limit.js';
import { requireConsent, requireUserId } from './auth.js';

const requestSchema = z.object({
  situation: z.string().min(3).max(2000),
  answers: z.record(z.string()).optional(),
  locale: z.string().max(12).default('en'),
});

export async function guidanceRoutes(app: FastifyInstance): Promise<void> {
  app.post('/guidance', async (request, reply) => {
    const userId = await requireUserId(request);
    await requireConsent(userId);
    // Each request here is paid for at the AI provider; a daily cap per
    // account keeps one account from running up the bill.
    if (!(await allow(`guidance:${userId}`, 30, DAY))) {
      return reply.status(429).send({ error: 'You have asked for the most plans Covera can make in one day. Try again tomorrow.' });
    }
    const parsed = requestSchema.safeParse(request.body);

    if (!parsed.success) {
      return reply.status(400).send({ error: 'Describe the situation in a sentence or two.' });
    }

    const { plan, withheld, usedOcrPages } = await buildGuidance({
      userId,
      situation: parsed.data.situation,
      locale: parsed.data.locale,
      ...(parsed.data.answers ? { answers: parsed.data.answers } : {}),
    });

    return reply.send({
      // The disclaimer travels with the guidance itself so no client can render
      // a plan without it.
      disclaimer: disclaimerFor(parsed.data.locale),
      clarifying_questions: plan.clarifying_questions,
      summary: plan.summary,
      steps: plan.steps,
      conflicts: plan.conflicts,
      phone_script: plan.phone_script,
      draft_claim_email: plan.draft_claim_email,
      relevant_policy_ids: plan.relevant_policy_ids,
      withheld,
      // Some evidence came from a scanned page we transcribed ourselves, which
      // is a weaker guarantee than a document with a real text layer.
      includes_transcribed_pages: usedOcrPages,
    });
  });
}
