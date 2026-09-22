import { getDocumentProxy } from 'unpdf';

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
  let pdf: Awaited<ReturnType<typeof getDocumentProxy>>;
  try {
    pdf = await getDocumentProxy(new Uint8Array(file));
  } catch (error) {
    // A damaged or password-protected file. Named, so the route can tell the
    // user what went wrong instead of answering with a server error.
    throw new UnreadablePdfError(error instanceof Error ? error.message : String(error));
  }

  const pages: PageText[] = [];
  for (let number = 1; number <= pdf.numPages; number++) {
    const page = await pdf.getPage(number);
    const content = await page.getTextContent();
    pages.push({ page: number, text: layoutText(content.items as TextItem[]).trim(), ocr: false });
  }

  const needsOcr = pages
    .filter((p) => p.text.length < TEXT_LAYER_MIN_CHARS)
    .map((p) => p.page);

  return { pages, needsOcr };
}

export class UnreadablePdfError extends Error {
  constructor(detail: string) {
    super(`The PDF could not be opened: ${detail}`);
    this.name = 'UnreadablePdfError';
  }
}

interface TextItem {
  str: string;
  transform: number[];
  width: number;
  height: number;
  hasEOL?: boolean;
}

/**
 * Rebuilds a page's text from positioned runs.
 *
 * Many PDF generators, and most that set Hebrew or Arabic, do not store space
 * characters: each word is placed at its own position. Joining the runs as
 * stored glues every word together ("מגדלורביטוח"), which breaks search and
 * makes every quote unverifiable. A space goes wherever two runs on a line are
 * visibly apart, and a line break wherever the baseline moves. Measured in both
 * directions, so right-to-left lines work too.
 */
export function layoutText(items: TextItem[]): string {
  let out = '';
  let previous: TextItem | null = null;

  for (const item of items) {
    if (item.str.length === 0) {
      if (item.hasEOL) out += '\n';
      continue;
    }

    if (previous) {
      const size = fontSize(item) || fontSize(previous) || 10;
      const sameLine = Math.abs(item.transform[5]! - previous.transform[5]!) < size * 0.5;

      if (!sameLine) {
        if (!out.endsWith('\n')) out += '\n';
      } else {
        const prevStart = previous.transform[4]!;
        const prevEnd = prevStart + previous.width;
        const start = item.transform[4]!;
        const end = start + item.width;
        // Gap between the two runs, whichever side the new one is on.
        const gap = Math.max(start - prevEnd, prevStart - end);
        const spaced = /\s$/.test(out) || /^\s/.test(item.str);
        if (gap > size * 0.15 && !spaced) out += ' ';
      }
    }

    out += item.str;
    if (item.hasEOL) out += '\n';
    previous = item;
  }

  return out.replace(/[ \t]+\n/g, '\n');
}

function fontSize(item: TextItem): number {
  return Math.hypot(item.transform[2] ?? 0, item.transform[3] ?? 0) || item.height;
}
