import { describe, expect, it } from 'vitest';
import { snapQuote } from './snap.js';

// Page text as a Hebrew PDF's text layer stores it: numbers ahead of their
// labels, direction marks around runs. Modelled on a real policy's layout;
// the figures are invented.
const PAGE = [
  '‫824142717 מס\' פוליסה:‬',
  '6/2026 מדד הדפסה:',
  'ההשתתפות העצמית היא 20% ולא יותר מ- 478.58 ש"ח',
  'תקרת הכיסוי לתרופות מיוחדות היא 1,196,454.00 ש"ח לשנה',
  'Section 2.2 The surgeon\'s fee is limited to 30,000 per procedure.',
].join('\n');

describe('snapping a quote to the page text', () => {
  it('fixes a Hebrew quote whose number and label were reordered', () => {
    expect(snapQuote("מס' פוליסה: 824142717", PAGE)).toBe("824142717 מס' פוליסה:");
  });

  it('fixes typing slips that are not about figures', () => {
    expect(snapQuote('Section 2.2 The surgeon\'s fee is limited to 30,000 per procedúre.', PAGE))
      .toBe('Section 2.2 The surgeon\'s fee is limited to 30,000 per procedure.');
    expect(snapQuote('ההשתתפות העצמית היא 20% ולא יותר מ-478.58 ש״ח', PAGE))
      .toBe('ההשתתפות העצמית היא 20% ולא יותר מ- 478.58 ש"ח');
  });

  it('never snaps when a figure in the quote is not printed on the page', () => {
    // Same words, different amount: this must stay unverifiable.
    expect(snapQuote('ההשתתפות העצמית היא 25% ולא יותר מ- 478.58 ש"ח', PAGE)).toBeNull();
    expect(snapQuote('The surgeon\'s fee is limited to 40,000 per procedure.', PAGE)).toBeNull();
  });

  it('never snaps a quote the page does not contain', () => {
    expect(snapQuote('[מועד החידוש הקרוב הינו 1 ביוני 2028]', PAGE)).toBeNull();
    expect(snapQuote('Cosmetic surgery is excluded from this plan.', PAGE)).toBeNull();
  });

  it('splits words that a direction mark glued to a number without a space', () => {
    // As stored by a PDF generator: label and number joined by U+202A only,
    // and the colon moved past the number.
    const page = "\u202bמס' פוליסה\u202a55012345 :\u202c\u202c";
    expect(snapQuote("מס' פוליסה: 55012345", page)).toBe("מס' פוליסה55012345 :");
  });

  it('leaves an exact quote alone', () => {
    expect(snapQuote('6/2026 מדד הדפסה:', PAGE)).toBeNull();
  });

  it('does not snap very short quotes, which cannot identify a passage', () => {
    expect(snapQuote('20% ש"ח', PAGE)).toBeNull();
  });
});
