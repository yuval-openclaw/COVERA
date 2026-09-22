import { z } from 'zod';
import { sourceCitationSchema } from '../schema/policy.js';

/**
 * Guidance output carries the same guarantee as extraction: a step may assert a
 * figure only with a citation, or must say plainly that the policy is silent
 * and hand the user the insurer's number. Those are the only two shapes.
 */

const citedBasisSchema = z.object({
  kind: z.literal('cited'),
  citation: sourceCitationSchema,
});

const notStatedBasisSchema = z.object({
  kind: z.literal('not_stated'),
  /** What the user should ask, since we cannot answer it from their documents. */
  ask_insurer: z.string().min(1),
  insurer_phone: z.string().nullable(),
});

/** General procedure that asserts nothing about this user's coverage. */
const generalBasisSchema = z.object({
  kind: z.literal('general'),
});

export const stepBasisSchema = z.discriminatedUnion('kind', [
  citedBasisSchema,
  notStatedBasisSchema,
  generalBasisSchema,
]);

export const actionStepSchema = z.object({
  order: z.number().int().positive(),
  action: z.string().min(1),
  /** Only ever copied from a cited deadline; never estimated. */
  deadline_note: z.string().nullable(),
  basis: stepBasisSchema,
});
export type ActionStep = z.infer<typeof actionStepSchema>;

export const clarifyingQuestionSchema = z.object({
  question: z.string().min(1),
  why: z.string().min(1),
});

export const guidancePlanSchema = z.object({
  /** Asked before planning when the answer would change the plan materially. */
  clarifying_questions: z.array(clarifyingQuestionSchema),
  relevant_policy_ids: z.array(z.string().uuid()),
  summary: z.string().min(1),
  steps: z.array(actionStepSchema),
  /** Conflicts between policies are surfaced, never silently resolved. */
  conflicts: z.array(z.string()),
  phone_script: z.string().nullable(),
  draft_claim_email: z.string().nullable(),
});
export type GuidancePlan = z.infer<typeof guidancePlanSchema>;

const DISCLAIMERS: Record<string, string> = {
  fr: "Covera n'est ni médecin ni agent d'assurance agréé. Il s'agit d'une lecture de vos propres documents, pas d'un avis médical ni d'une décision de couverture. Votre assureur décide de ce qui est couvert.",
  de: "Covera ist weder Arzt noch zugelassener Versicherungsmakler. Dies ist eine Lesart Ihrer eigenen Dokumente, keine medizinische Beratung und keine Entscheidung über den Versicherungsschutz. Was übernommen wird, entscheidet Ihre Versicherung.",
  pt: "Covera não é médico nem corretor de seguros licenciado. Esta é uma leitura dos seus próprios documentos, não um aconselhamento médico nem uma decisão de cobertura. Sua seguradora decide o que é coberto.",
  he: "Covera אינה רופא ואינה סוכן ביטוח מורשה. זוהי קריאה של המסמכים שלך בלבד, לא ייעוץ רפואי ולא החלטת כיסוי. חברת הביטוח שלך קובעת מה מכוסה.",
  ar: "Covera ليس طبيبًا ولا وكيل تأمين مرخّصًا. هذه قراءة لمستنداتك الخاصة، وليست نصيحة طبية ولا قرار تغطية. شركة التأمين هي من تقرر ما هو مغطى.",
  hi: "Covera न तो डॉक्टर है और न ही लाइसेंसधारी बीमा एजेंट। यह आपके अपने दस्तावेज़ों का पठन है, चिकित्सा सलाह या कवरेज निर्णय नहीं। क्या कवर है, यह आपका बीमाकर्ता तय करता है।",
  th: "Covera ไม่ใช่แพทย์และไม่ใช่ตัวแทนประกันที่ได้รับอนุญาต นี่คือการอ่านเอกสารของคุณเอง ไม่ใช่คำแนะนำทางการแพทย์หรือการตัดสินความคุ้มครอง บริษัทประกันของคุณเป็นผู้ตัดสินว่าอะไรได้รับความคุ้มครอง",
  ja: "Coveraは医師でも認可を受けた保険代理店でもありません。これはご自身の書類の読み取りであり、医療上の助言や補償の判断ではありません。何が補償されるかは保険会社が決定します。",
  es: 'Covera no es médico ni agente de seguros autorizado. Esto es una lectura de sus propios documentos, no un consejo médico ni una decisión de cobertura. Su aseguradora decide qué está cubierto.',
};

export function disclaimerFor(locale: string): string {
  return DISCLAIMERS[locale.slice(0, 2)] ?? DISCLAIMER;
}

export const DISCLAIMER =
  'Covera is not a doctor and not a licensed insurance agent. This is a reading of your own documents, not medical advice and not a coverage decision. Your insurer decides what is covered.';
