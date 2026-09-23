import { describe, expect, it } from 'vitest';
import { contentDisposition } from './filename.js';

// The stored filename is whatever the client called its upload, so it reaches
// this header as attacker-controlled text.
describe('contentDisposition', () => {
  it('keeps a plain filename', () => {
    expect(contentDisposition('policy.pdf')).toBe(
      `attachment; filename="policy.pdf"; filename*=UTF-8''policy.pdf`,
    );
  });

  it('strips CR and LF so the value cannot inject another header', () => {
    const value = contentDisposition('a\r\nSet-Cookie: x=1.pdf');
    expect(value).not.toMatch(/[\r\n]/);
  });

  it('never emits a bare quote or backslash in the ascii filename', () => {
    const ascii = contentDisposition('he said "hi"\\.pdf').match(/filename="([^"]*)"/)?.[1] ?? '';
    expect(ascii).not.toMatch(/["\\]/);
  });

  it('carries a non-ASCII name in filename* and falls back in filename', () => {
    const value = contentDisposition('פוליסה.pdf');
    expect(value).toContain(`filename*=UTF-8''${encodeURIComponent('פוליסה.pdf')}`);
    // The ascii fallback holds no raw non-ASCII bytes.
    const ascii = value.match(/filename="([^"]*)"/)?.[1] ?? '';
    expect(ascii).toMatch(/^[\x20-\x7e]*$/);
  });

  it('falls back to a default when nothing ascii survives', () => {
    expect(contentDisposition('\n\n')).toContain('filename="__"');
    expect(contentDisposition('')).toContain('filename="document.pdf"');
  });
});
