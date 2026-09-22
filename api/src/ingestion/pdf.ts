import { extractText, getDocumentProxy } from 'unpdf';

export interface PageText {
  page: number;
  text: string;
  /** True when the text came from OCR rather than an embedded text layer. */
  ocr: boolean;
}

/**
 * A page with almost no extractable text is a scan, not an empty page. Policy
 * pages carry dense prose, so this threshold separates the two reliably without
 * misclassifying a sparse cover page as needing OCR.
 */
const TEXT_LAYER_MIN_CHARS = 40;

export async function extractPdfPages(file: Buffer): Promise<{
  pages: PageText[];
  needsOcr: number[];
}> {
  const pdf = await getDocumentProxy(new Uint8Array(file));
  const { text } = await extractText(pdf, { mergePages: false });

  const pages: PageText[] = text.map((raw, index) => ({
    page: index + 1,
    text: raw.trim(),
    ocr: false,
  }));

  const needsOcr = pages
    .filter((p) => p.text.length < TEXT_LAYER_MIN_CHARS)
    .map((p) => p.page);

  return { pages, needsOcr };
}
