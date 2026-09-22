import 'server-only';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { randomUUID } from 'node:crypto';

/**
 * Mock database: a single JSON file on disk (data/db.json), created and seeded on
 * first use. Every read of user-owned data goes through `ownerId`, so one account
 * can never see another's library. Swap this module for a real DB later — the
 * route handlers only use the exported functions.
 */

export type Category = 'shirt' | 'pants' | 'underwear' | 'socks' | 'dress' | 'sweater' | 'other';

export const CATEGORIES: Record<Category, { he: string; emoji: string; gender: 'm' | 'f' }> = {
  shirt: { he: 'חולצה', emoji: '👕', gender: 'f' },
  pants: { he: 'מכנסיים', emoji: '👖', gender: 'm' },
  underwear: { he: 'תחתונים', emoji: '🩲', gender: 'm' },
  socks: { he: 'גרב', emoji: '🧦', gender: 'f' },
  dress: { he: 'שמלה', emoji: '👗', gender: 'f' },
  sweater: { he: 'סוודר', emoji: '🧥', gender: 'm' },
  other: { he: 'פריט', emoji: '🧺', gender: 'm' },
};

export interface User {
  id: string;
  kind: 'account' | 'guest';
  email?: string;
  passwordHash?: string; // scrypt, "salt:hash"
  accessCode: string;
  createdAt: string;
}

export interface Person {
  id: string;
  ownerId: string;
  name: string; // shown as-is, e.g. "אייל"
  color: string;
}

export interface ClothingItem {
  id: string;
  ownerId: string;
  personId: string;
  category: Category;
  /** Micro-features the vision model wrote, e.g. "גרב לבנה, קרע קטן בעקב". */
  features: string;
  size?: string;
  colors: string[];
  thumbnail?: string; // small JPEG data URL; seeded demo items have none
  createdAt: string;
}

interface Session {
  tokenHash: string;
  userId: string;
  expiresAt: string;
}

interface Schema {
  users: User[];
  sessions: Session[];
  people: Person[];
  items: ClothingItem[];
}

const FILE = path.join(process.cwd(), 'data', 'db.json');
// Soft, distinguishable tones; text on them is always near-black.
const PALETTE = ['#E9B8A2', '#A9C4E4', '#E7D39B', '#B7D3C0', '#CBB9E3', '#EFB6C6'];

let cache: Schema | null = null;
let writing: Promise<void> = Promise.resolve();

async function load(): Promise<Schema> {
  if (cache) return cache;
  try {
    cache = JSON.parse(await fs.readFile(FILE, 'utf8')) as Schema;
  } catch {
    cache = { users: [], sessions: [], people: [], items: [] };
  }
  return cache;
}

/** Serialised writes: concurrent requests never interleave a half-written file. */
async function save(): Promise<void> {
  const snapshot = JSON.stringify(cache, null, 2);
  writing = writing.then(async () => {
    await fs.mkdir(path.dirname(FILE), { recursive: true });
    const tmp = `${FILE}.${process.pid}.tmp`;
    await fs.writeFile(tmp, snapshot);
    await fs.rename(tmp, FILE);
  });
  return writing;
}

const now = () => new Date().toISOString();

// ── users & sessions ────────────────────────────────────────────────────────

export async function createUser(input: Omit<User, 'id' | 'createdAt'>): Promise<User> {
  const db = await load();
  const user: User = { ...input, id: randomUUID(), createdAt: now() };
  db.users.push(user);
  await save();
  return user;
}

export async function findUserByEmail(email: string) {
  return (await load()).users.find((u) => u.email === email.toLowerCase());
}

export async function findUserByAccessCode(code: string) {
  const norm = code.trim().toUpperCase();
  return (await load()).users.find((u) => u.accessCode === norm);
}

export async function findUser(id: string) {
  return (await load()).users.find((u) => u.id === id);
}

export async function accessCodeTaken(code: string) {
  return (await load()).users.some((u) => u.accessCode === code);
}

export async function addSession(tokenHash: string, userId: string, days: number) {
  const db = await load();
  const cutoff = now();
  db.sessions = db.sessions.filter((s) => s.expiresAt > cutoff);
  db.sessions.push({ tokenHash, userId, expiresAt: new Date(Date.now() + days * 864e5).toISOString() });
  await save();
}

export async function sessionUserId(tokenHash: string) {
  const s = (await load()).sessions.find((x) => x.tokenHash === tokenHash);
  return s && s.expiresAt > now() ? s.userId : undefined;
}

export async function removeSession(tokenHash: string) {
  const db = await load();
  db.sessions = db.sessions.filter((s) => s.tokenHash !== tokenHash);
  await save();
}

// ── library (always scoped by ownerId) ──────────────────────────────────────

export async function getLibrary(ownerId: string) {
  const db = await load();
  return {
    people: db.people.filter((p) => p.ownerId === ownerId),
    items: db.items.filter((i) => i.ownerId === ownerId),
  };
}

export async function addPerson(ownerId: string, name: string): Promise<Person> {
  const db = await load();
  const count = db.people.filter((p) => p.ownerId === ownerId).length;
  const person = { id: randomUUID(), ownerId, name, color: PALETTE[count % PALETTE.length] };
  db.people.push(person);
  await save();
  return person;
}

export async function addItem(
  ownerId: string,
  input: Omit<ClothingItem, 'id' | 'ownerId' | 'createdAt'>,
): Promise<ClothingItem | null> {
  const db = await load();
  if (!db.people.some((p) => p.id === input.personId && p.ownerId === ownerId)) return null;
  const item: ClothingItem = { ...input, id: randomUUID(), ownerId, createdAt: now() };
  db.items.push(item);
  await save();
  return item;
}

export async function deleteItem(ownerId: string, itemId: string) {
  const db = await load();
  const before = db.items.length;
  db.items = db.items.filter((i) => !(i.id === itemId && i.ownerId === ownerId));
  await save();
  return db.items.length < before;
}
