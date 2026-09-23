/**
 * A Content-Disposition value for a downloaded file. The stored filename is
 * whatever the client named its upload, so it cannot go into a header raw: a
 * newline would let it inject other headers, and a non-ASCII byte is not valid
 * in the quoted form. An ASCII-only `filename` covers old clients, and a
 * `filename*` (RFC 5987) carries the real name, percent-encoded.
 *
 * Kept free of any env or database import so it can be unit-tested directly.
 */
export function contentDisposition(name: string): string {
  const ascii = name.replace(/[^\x20-\x7e]/g, '_').replace(/["\\]/g, '_') || 'document.pdf';
  const encoded = encodeURIComponent(name);
  return `attachment; filename="${ascii}"; filename*=UTF-8''${encoded}`;
}
