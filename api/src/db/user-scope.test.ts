import { readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

/**
 * Per-user isolation, checked mechanically rather than by review.
 *
 * Every table below holds one person's health documents. A query that reads or
 * writes one of them without naming user_id is a cross-account leak waiting for
 * the right pair of ids, and it will not look wrong in a diff — it looks like a
 * query with one missing line. So the rule is enforced here: touch a
 * user-owned table in application code, name user_id in the same statement.
 *
 * Where a table genuinely has no user_id of its own (document_pages,
 * policy_members, claim_documents), the statement must reach ownership through
 * a join, which still means the string contains "user_id".
 *
 * Postgres RLS would enforce this in the database instead, and remains the
 * better answer; it is deferred because it needs a per-request session role.
 * Until then this test is the guard.
 */

const USER_OWNED = [
  'documents',
  'document_pages',
  'document_chunks',
  'policies',
  'policy_members',
  'members',
  'claims',
  'claim_documents',
];

const SRC = join(dirname(fileURLToPath(import.meta.url)), '..');

function sourceFiles(dir: string): string[] {
  return readdirSync(dir).flatMap((entry) => {
    const path = join(dir, entry);
    if (statSync(path).isDirectory()) return sourceFiles(path);
    if (!path.endsWith('.ts') || path.endsWith('.test.ts')) return [];
    return [path];
  });
}

/** Rough SQL statement extraction: template literals containing FROM/INTO/UPDATE. */
function statementsIn(source: string): string[] {
  const literals = source.match(/`[^`]*`/g) ?? [];
  return literals.filter((literal) => /\b(FROM|INTO|UPDATE|DELETE FROM)\b/i.test(literal));
}

describe('every query against a user-owned table is scoped to a user', () => {
  const files = sourceFiles(SRC).filter((f) => !f.includes('/migrations/'));

  it('finds application SQL to check (guards against the scan silently matching nothing)', () => {
    const total = files.flatMap((f) => statementsIn(readFileSync(f, 'utf8')));
    expect(total.length).toBeGreaterThan(5);
  });

  for (const table of USER_OWNED) {
    it(`scopes every statement touching ${table}`, () => {
      const unscoped: string[] = [];

      for (const file of files) {
        for (const statement of statementsIn(readFileSync(file, 'utf8'))) {
          const touches = new RegExp(`\\b(FROM|JOIN|INTO|UPDATE)\\s+${table}\\b`, 'i');
          if (!touches.test(statement)) continue;
          if (/\buser_id\b/.test(statement)) continue;
          unscoped.push(`${file.replace(SRC, 'src')}: ${statement.slice(0, 120)}`);
        }
      }

      expect(unscoped).toEqual([]);
    });
  }
});
