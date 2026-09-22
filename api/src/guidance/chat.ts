import { z } from 'zod';
import {
  generateJson,
  jsonSchemaFor,
  MODELS,
  modelTurn,
  textPart,
  userTurn,
  type Content,
} from '../ai/gemini.js';
import { sourceCitationSchema } from '../schema/policy.js';
import { checkAnswer } from './check-answer.js';
import { loadPagesForUser, retrieveSnippets } from './retrieve.js';

/**
 * Free-form questions about the user's own policies, held to the same rule as
 * everything else: an answer may state a figure only if a citation it carries
 * contains that figure, and every citation must be found on its page.
 */
const answerSchema = z.object({
  answer: z.string().min(1),
  citations: z.array(sourceCitationSchema),
  /** Set when the documents do not answer the question. */
  ask_insurer: z.string().nullable(),
});
export type ChatAnswer = z.infer<typeof answerSchema>;

export const chatMessageSchema = z.object({
  role: z.enum(['user', 'assistant']),
  content: z.string().min(1).max(4000),
});

const SYSTEM = `You answer questions about the user's own insurance documents, using only the snippets provided. You read their policies back to them; you do not advise.
1. Any figure (percentage, amount, cap, waiting period, deadline) must appear in a citation you attach, with verbatim_quote copied character-for-character from a snippet.
2. If the snippets do not answer the question, say so plainly and put the question they should ask their insurer in ask_insurer. Never fill gaps with how insurance usually works, and never put a figure in ask_insurer.
3. If the wording is ambiguous, show both readings. Never predict what will be approved. No medical advice.
4. Be brief and calm. Reply in the language named below; quotes stay in the document's original language.
5. Speak to the user about "your policy" or "your documents". Never mention snippets, excerpts, context or what you were provided — those are internals the user never sees.`;

const FALLBACK: Record<string, string> = {
  en: "I couldn't trace an answer to that in your documents, so I won't guess. Please ask your insurer.",
  fr: "Je n'ai pas trouvé de réponse vérifiable dans vos documents, je préfère ne pas deviner. Veuillez contacter votre assureur.",
  de: 'Ich habe in Ihren Dokumenten keine belegbare Antwort gefunden und rate nicht. Bitte fragen Sie Ihre Versicherung.',
  pt: 'Não encontrei uma resposta verificável nos seus documentos, então não vou adivinhar. Consulte sua seguradora.',
  he: 'לא מצאתי תשובה שניתן לאמת במסמכים שלך, ולכן לא אנחש. פנה לחברת הביטוח שלך.',
  ar: 'لم أجد إجابة يمكن التحقق منها في مستنداتك، لذلك لن أخمّن. يُرجى سؤال شركة التأمين.',
  hi: 'आपके दस्तावेज़ों में इसका सत्यापित उत्तर नहीं मिला, इसलिए मैं अनुमान नहीं लगाऊँगा। कृपया अपने बीमाकर्ता से पूछें।',
  th: 'ไม่พบคำตอบที่ตรวจสอบได้ในเอกสารของคุณ จึงจะไม่เดา โปรดสอบถามบริษัทประกันของคุณ',
  ja: 'お手元の書類から確認できる回答が見つからなかったため、推測はしません。保険会社にお問い合わせください。',
  es: 'No encontré una respuesta verificable en sus documentos, así que no voy a adivinar. Consulte a su aseguradora.',
};

export async function answerQuestion(params: {
  userId: string;
  messages: z.infer<typeof chatMessageSchema>[];
  locale: string;
}): Promise<ChatAnswer & { withheld: boolean }> {
  const { userId, messages, locale } = params;
  const code = locale.slice(0, 2);
  const language = code in FALLBACK ? code : 'en';
  const question = messages.filter((m) => m.role === 'user').at(-1)?.content ?? '';

  const snippets = await retrieveSnippets(userId, question);
  const pages = await loadPagesForUser(userId, [...new Set(snippets.map((s) => s.documentId))]);
  const evidence = snippets.length
    ? snippets.map((s) => `[document_id: ${s.documentId} | page: ${s.page}]\n${s.text}`).join('\n\n---\n\n')
    : '(No policy text matched this question.)';

  const schema = jsonSchemaFor(answerSchema);
  const contents: Content[] = [
    userTurn(textPart(`Snippets:\n\n${evidence}`)),
    modelTurn('Understood. I will only use these snippets.'),
    ...messages.map((m) => (m.role === 'user' ? userTurn(textPart(m.content)) : modelTurn(m.content))),
  ];

  for (let attempt = 1; attempt <= 2; attempt++) {
    const { raw, value } = await generateJson({
      model: MODELS.fast,
      system: `${SYSTEM}\nLanguage: ${language}`,
      contents,
      schema,
      maxOutputTokens: 4000,
    });

    const parsed = answerSchema.safeParse(value);
    const problems = parsed.success ? checkAnswer(parsed.data, pages) : ['the answer did not match the schema'];
    if (parsed.success && problems.length === 0) return { ...parsed.data, withheld: false };

    contents.push(
      modelTurn(raw),
      userTurn(
        textPart(`Rejected: ${problems.join('; ')}. Quote exactly, remove unsupported figures, or use ask_insurer. Return corrected JSON.`),
      ),
    );
  }

  // An answer we could not verify is replaced, not shown with a caveat.
  return { answer: FALLBACK[language]!, citations: [], ask_insurer: null, withheld: true };
}
