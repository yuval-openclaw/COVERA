import type { ZodTypeAny } from 'zod';
import { zodToJsonSchema } from 'zod-to-json-schema';
import { env } from '../config/env.js';

/**
 * Gemini, called over REST rather than through an SDK: two endpoints are all
 * the app needs, and a hand-rolled call keeps the request auditable — exactly
 * what leaves the server with a user's health documents is visible here.
 */
export const GEMINI_BASE = 'https://generativelanguage.googleapis.com/v1beta';

export const MODELS = {
  /** Citation fidelity is the product, so extraction and plans use the strongest model. */
  extraction: env.GEMINI_MODEL,
  guidance: env.GEMINI_MODEL,
  /** Chat answers. Still mechanically verified, so a faster model is safe here. */
  fast: env.GEMINI_FAST_MODEL,
} as const;

export type Part = { text: string } | { inlineData: { mimeType: string; data: string } };
export interface Content {
  role: 'user' | 'model';
  parts: Part[];
}

export const textPart = (text: string): Part => ({ text });
export const pdfPart = (pdf: Buffer): Part => ({
  inlineData: { mimeType: 'application/pdf', data: pdf.toString('base64') },
});
export const userTurn = (...parts: Part[]): Content => ({ role: 'user', parts });
/** The model's previous reply, replayed so a correction can refer to it. */
export const modelTurn = (raw: string): Content => ({ role: 'model', parts: [{ text: raw }] });

/** The same zod schema that validates the output also constrains it. */
export function jsonSchemaFor(schema: ZodTypeAny): Record<string, unknown> {
  const { $schema: _dialect, ...rest } = zodToJsonSchema(schema, { $refStrategy: 'none' }) as Record<
    string,
    unknown
  >;
  return constToEnum(rest) as Record<string, unknown>;
}

/**
 * zod emits `const` for literals, which Gemini does not enforce: on the first
 * live call the discriminators (`status`, `kind`) came back with values of the
 * model's own choosing. A one-item `enum` says the same thing and is enforced.
 * (No schema here has a property literally named "const".)
 */
function constToEnum(node: unknown): unknown {
  if (Array.isArray(node)) return node.map(constToEnum);
  if (node === null || typeof node !== 'object') return node;

  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(node)) out[key] = constToEnum(value);

  if ('const' in out) {
    const value = out.const;
    delete out.const;
    out.enum = [value];
    if (!('type' in out) && typeof value === 'string') out.type = 'string';
  }
  return out;
}

interface GenerateResponse {
  candidates?: {
    finishReason?: string;
    content?: { parts?: { text?: string; thought?: boolean }[] };
  }[];
  promptFeedback?: { blockReason?: string };
}

/**
 * One structured-output call. `value` is `undefined` when the reply is not
 * valid JSON, so callers treat it like any other schema failure and feed the
 * problem back rather than crashing.
 */
export async function generateJson(params: {
  model: string;
  system: string;
  contents: Content[];
  schema: Record<string, unknown>;
  maxOutputTokens?: number;
  /**
   * When false, the schema is given to the model as instructions rather than
   * as a decoding constraint — for schemas too large for Gemini to compile
   * ("too many states"). Output is validated by zod and the citation verifier
   * either way, so this changes how often a repair round is needed, never what
   * reaches a user.
   */
  constrain?: boolean;
}): Promise<{ raw: string; value: unknown }> {
  const constrain = params.constrain ?? true;
  const system = constrain
    ? params.system
    : `${params.system}\n\nReturn only JSON that conforms to this JSON Schema:\n${JSON.stringify(params.schema)}`;

  const response = await fetch(`${GEMINI_BASE}/models/${params.model}:generateContent`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-goog-api-key': env.COVERA_GEMINI_API_KEY },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: system }] },
      contents: params.contents,
      generationConfig: {
        responseMimeType: 'application/json',
        ...(constrain ? { responseJsonSchema: params.schema } : {}),
        // Transcription, not composition: the same page should read the same way twice.
        temperature: 0,
        maxOutputTokens: params.maxOutputTokens ?? 16000,
      },
    }),
  });

  if (!response.ok) {
    // Error bodies describe the request, not the document, so a short excerpt
    // is safe to surface.
    throw new Error(`Gemini request failed (${response.status}): ${(await response.text()).slice(0, 400)}`);
  }

  const body = (await response.json()) as GenerateResponse;
  const candidate = body.candidates?.[0];
  if (!candidate) {
    const reason = body.promptFeedback?.blockReason;
    throw new Error(`Gemini returned no answer${reason ? ` (blocked: ${reason})` : ''}`);
  }
  // A reply cut off by a token limit or a safety stop is a partial structure;
  // accepting it could silently drop the one clause that mattered.
  if (candidate.finishReason && candidate.finishReason !== 'STOP') {
    throw new Error(`Gemini stopped before finishing (${candidate.finishReason})`);
  }

  const raw = (candidate.content?.parts ?? [])
    .filter((p) => typeof p.text === 'string' && !p.thought)
    .map((p) => p.text)
    .join('');

  try {
    return { raw, value: JSON.parse(raw) };
  } catch {
    return { raw, value: undefined };
  }
}
