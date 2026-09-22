'use client';

export type Category = 'shirt' | 'pants' | 'underwear' | 'socks' | 'dress' | 'sweater' | 'other';

export const CATEGORY_UI: Record<Category, { he: string; emoji: string }> = {
  shirt: { he: 'חולצה', emoji: '👕' },
  pants: { he: 'מכנסיים', emoji: '👖' },
  underwear: { he: 'תחתונים', emoji: '🩲' },
  socks: { he: 'גרב', emoji: '🧦' },
  dress: { he: 'שמלה', emoji: '👗' },
  sweater: { he: 'סוודר', emoji: '🧥' },
  other: { he: 'אחר', emoji: '🧺' },
};

export interface User { id: string; kind: 'account' | 'guest'; email?: string; accessCode: string }
export interface Person { id: string; name: string; color: string }
export interface Item {
  id: string; personId: string; category: Category; features: string;
  size?: string; colors: string[]; thumbnail?: string; createdAt: string;
}
export interface ScanResult {
  analysis: { category: Category; features: string; size?: string; colors: string[] };
  match: { itemId: string; personId: string; personName: string; confidence: number; reasoning: string } | null;
  verdict: string;
  confident: boolean;
  demo: boolean;
}

export class ApiError extends Error {
  constructor(public status: number, message: string) { super(message); }
}

export async function api<T>(path: string, init?: { method?: string; body?: unknown }): Promise<T> {
  const res = await fetch(path, {
    method: init?.method ?? (init?.body ? 'POST' : 'GET'),
    headers: init?.body ? { 'content-type': 'application/json' } : undefined,
    body: init?.body ? JSON.stringify(init.body) : undefined,
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new ApiError(res.status, data.error ?? 'משהו השתבש');
  return data as T;
}

/** Downscales on the device so uploads stay small; returns a JPEG data URL. */
export async function resizeImage(source: Blob | HTMLCanvasElement, maxSide: number, quality = 0.85) {
  let bitmap: ImageBitmap | HTMLCanvasElement;
  if (source instanceof Blob) {
    // Browsers without createImageBitmap orientation support still get a usable image.
    bitmap = await createImageBitmap(source, { imageOrientation: 'from-image' });
  } else {
    bitmap = source;
  }
  const scale = Math.min(1, maxSide / Math.max(bitmap.width, bitmap.height));
  const canvas = document.createElement('canvas');
  canvas.width = Math.round(bitmap.width * scale);
  canvas.height = Math.round(bitmap.height * scale);
  canvas.getContext('2d')!.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  return canvas.toDataURL('image/jpeg', quality);
}

// ── access-code prompt state, remembered per user on this device ────────────

type PromptState = { copied?: boolean; dismissals?: number };
const key = (userId: string) => `cl_code_prompt_${userId}`;

export function readPromptState(userId: string): PromptState {
  try { return JSON.parse(localStorage.getItem(key(userId)) ?? '{}'); } catch { return {}; }
}

export function writePromptState(userId: string, state: PromptState) {
  try { localStorage.setItem(key(userId), JSON.stringify(state)); } catch { /* private mode */ }
}

export async function copyText(text: string) {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    // Older mobile browsers / insecure origins.
    const ta = document.createElement('textarea');
    ta.value = text;
    ta.style.position = 'fixed';
    ta.style.opacity = '0';
    document.body.appendChild(ta);
    ta.select();
    const ok = document.execCommand('copy');
    ta.remove();
    return ok;
  }
}
