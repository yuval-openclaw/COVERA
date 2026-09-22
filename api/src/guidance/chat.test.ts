import { describe, expect, it } from 'vitest';
import { checkAnswer } from './check-answer.js';

const DOC = '11111111-1111-4111-8111-111111111111';
const pages = new Map([[DOC, new Map([[3, 'Dental treatment is reimbursed at 70%, up to 2,000 per year.']])]]);
const cite = (q: string, page = 3) => ({ document_id: DOC, page, clause_ref: null, verbatim_quote: q });

describe('chat answers obey the citation rule', () => {
  it('accepts a figure its citation contains', () => {
    expect(checkAnswer({ answer: 'Dental is reimbursed at 70%.', citations: [cite('reimbursed at 70%')], ask_insurer: null }, pages)).toEqual([]);
  });
  it('rejects a figure with no citation behind it', () => {
    expect(checkAnswer({ answer: 'You get 90% back.', citations: [], ask_insurer: null }, pages)).toHaveLength(1);
  });
  it('rejects a quote not on its page', () => {
    expect(checkAnswer({ answer: 'Covered.', citations: [cite('fully covered', 3)], ask_insurer: null }, pages)).toHaveLength(1);
  });
  it('rejects a figure smuggled into the insurer question', () => {
    expect(checkAnswer({ answer: 'Not stated.', citations: [], ask_insurer: 'Is the 6 month wait waived?' }, pages)).toHaveLength(1);
  });
});
