import { describe, expect, it } from 'vitest';
import { chunkPages } from './chunk.js';
import type { PageText } from './pdf.js';

const page = (page: number, text: string): PageText => ({ page, text, ocr: false });

describe('chunking', () => {
  it('keeps every chunk attributable to exactly one page', () => {
    const chunks = chunkPages([
      page(1, 'Clause one. '.repeat(300)),
      page(2, 'Clause two. '.repeat(300)),
    ]);

    const pagesForText = (needle: string) =>
      new Set(chunks.filter((c) => c.text.includes(needle)).map((c) => c.page));

    expect(pagesForText('Clause one')).toEqual(new Set([1]));
    expect(pagesForText('Clause two')).toEqual(new Set([2]));
  });

  it('overlaps consecutive chunks so a clause split by a cut stays retrievable', () => {
    const chunks = chunkPages([page(1, 'Sentence about surgery. '.repeat(200))]);

    expect(chunks.length).toBeGreaterThan(1);
    const first = chunks[0]!.text;
    const second = chunks[1]!.text;
    const tail = first.slice(-60);
    expect(second.includes(tail.trim().split(' ').slice(-3).join(' '))).toBe(true);
  });

  it('emits a single chunk for a short page', () => {
    const chunks = chunkPages([page(1, 'Policy schedule for Example Assurance.')]);
    expect(chunks).toHaveLength(1);
    expect(chunks[0]?.text).toBe('Policy schedule for Example Assurance.');
  });

  it('skips blank pages rather than embedding empty text', () => {
    expect(chunkPages([page(1, '   \n  '), page(2, 'Real content here.')])).toHaveLength(1);
  });

  it('numbers chunks continuously across pages', () => {
    const chunks = chunkPages([page(1, 'a. '.repeat(700)), page(2, 'b. '.repeat(700))]);
    expect(chunks.map((c) => c.chunkIndex)).toEqual(chunks.map((_, i) => i));
  });
});
