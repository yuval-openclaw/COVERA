import { z } from 'zod';
import { generateJson, jsonSchemaFor, MODELS, pdfPart, textPart, userTurn } from '../ai/gemini.js';
import type { PageText } from './pdf.js';

/**
 * Scanned pages carry no text layer, so their text is transcribed from the
 * image. Citation verification then compares quotes against this transcription
 * rather than against the original — a weaker guarantee than a native text
 * layer. Pages transcribed here are marked `ocr: true` so downstream code can
 * surface that difference instead of implying equal certainty.
 */

const SYSTEM_PROMPT = `You transcribe scanned document pages. Reproduce the text exactly as printed: same wording, same numbers, same order, including headings, table cells and footnotes.

Do not summarise, correct, reorder or translate. If a character is illegible, write [illegible] in its place rather than guessing — a guessed digit in an insurance policy is a serious error. Return only the transcription.`;

const transcriptionSchema = z.object({
  pages: z.array(z.object({ page: z.number().int().positive(), text: z.string() })),
});

export async function ocrPages(pdf: Buffer, pageNumbers: number[]): Promise<PageText[]> {
  if (pageNumbers.length === 0) return [];

  const { value } = await generateJson({
    // Transcription feeds citation verification directly, so it gets the strong model.
    model: MODELS.extraction,
    system: SYSTEM_PROMPT,
    contents: [
      userTurn(pdfPart(pdf), textPart(`Transcribe these pages verbatim: ${pageNumbers.join(', ')}.`)),
    ],
    schema: jsonSchemaFor(transcriptionSchema),
    maxOutputTokens: 32768,
  });

  const parsed = transcriptionSchema.safeParse(value);
  if (!parsed.success) {
    throw new Error('Transcription returned no usable structured output');
  }

  const requested = new Set(pageNumbers);
  return parsed.data.pages
    .filter((p) => requested.has(p.page))
    .map((p) => ({ page: p.page, text: p.text.trim(), ocr: true }));
}
