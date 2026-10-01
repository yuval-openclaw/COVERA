import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { answerQuestion, chatMessageSchema } from '../guidance/chat.js';
import { disclaimerFor } from '../guidance/schema.js';
import { allow, DAY } from '../auth/rate-limit.js';
import { requireConsent, requireUserId } from './auth.js';

const requestSchema = z.object({
  messages: z.array(chatMessageSchema).min(1).max(20),
  locale: z.string().max(12).default('en'),
});

export async function chatRoutes(app: FastifyInstance): Promise<void> {
  app.post('/chat', async (request, reply) => {
    const userId = await requireUserId(request);
    await requireConsent(userId);
    // Each request here is paid for at the AI provider; a daily cap per
    // account keeps one account from running up the bill.
    if (!(await allow(`chat:${userId}`, 150, DAY))) {
      return reply.status(429).send({ error: 'You have asked the most questions Clausa can answer in one day. Try again tomorrow.' });
    }
    const parsed = requestSchema.safeParse(request.body);
    if (!parsed.success) return reply.status(400).send({ error: 'Ask a question about your policies.' });

    const result = await answerQuestion({ userId, ...parsed.data });
    // The disclaimer travels with every answer, as with plans.
    return reply.send({ ...result, disclaimer: disclaimerFor(parsed.data.locale) });
  });
}
