import 'server-only';
import { createHash } from 'node:crypto';
import { CATEGORIES, type Category, type ClothingItem, type Person } from './db';

export interface ScanAnalysis {
  category: Category;
  features: string; // Hebrew, micro-features only
  size?: string;
  colors: string[];
}

export interface ScanResult {
  analysis: ScanAnalysis;
  match: {
    itemId: string;
    personId: string;
    personName: string;
    confidence: number;
    reasoning: string;
  } | null;
  /** The sentence shown to the user, e.g. "זאת הגרב של אייל". */
  verdict: string;
  confident: boolean;
  demo: boolean;
}

/** Below this the app says "not sure" instead of naming an owner. */
const MIN_CONFIDENCE = 0.6;

const ARTICLE: Record<Category, { sg: string; pron: string }> = {
  shirt: { sg: 'החולצה', pron: 'זאת' },
  pants: { sg: 'המכנס', pron: 'זה' },
  underwear: { sg: 'התחתון', pron: 'זה' },
  socks: { sg: 'הגרב', pron: 'זאת' },
  dress: { sg: 'השמלה', pron: 'זאת' },
  sweater: { sg: 'הסוודר', pron: 'זה' },
  other: { sg: 'הפריט', pron: 'זה' },
};

export function verdictSentence(category: Category, name: string) {
  const a = ARTICLE[category];
  return `${a.pron} ${a.sg} של ${name}`;
}

const MAX_REFERENCE_IMAGES = 16;

const SYSTEM = `You identify which household member owns a clothing item by comparing
micro-features: exact size markings, tears, holes, pilling, stains, fading, stretched
elastic, wrinkles, missing buttons, cut labels, repairs, logos and fabric wear.
Colour and garment type alone are NOT enough to claim a match — many items share them.
Only claim a match when at least one distinctive micro-feature agrees with a library
item and none clearly contradicts it. If nothing in the library fits, return
match_index = -1. Never invent features that are not visible in the photo.
Write "features", "reasoning" and "colors" in Hebrew. Put the most distinctive feature first.`;

const RESPONSE_SCHEMA = {
  type: 'OBJECT',
  properties: {
    category: { type: 'STRING', enum: Object.keys(CATEGORIES) },
    features: { type: 'STRING', description: 'Hebrew micro-feature description of the photographed item' },
    size: { type: 'STRING', description: 'Size label if readable in the photo, else empty' },
    colors: { type: 'ARRAY', items: { type: 'STRING' }, description: 'Colour names in Hebrew' },
    match_index: { type: 'INTEGER', description: 'Index of the matching library item, or -1' },
    confidence: { type: 'NUMBER', description: '0 to 1' },
    reasoning: { type: 'STRING', description: 'Hebrew: which micro-features agree or differ' },
  },
  required: ['category', 'features', 'colors', 'match_index', 'confidence', 'reasoning'],
};

interface ModelOutput {
  category: Category;
  features: string;
  size?: string;
  colors: string[];
  match_index: number;
  confidence: number;
  reasoning: string;
}

function splitDataUrl(dataUrl: string) {
  const m = /^data:(image\/[a-z+]+);base64,(.+)$/.exec(dataUrl);
  if (!m) throw new Error('bad image');
  return { mime_type: m[1], data: m[2] };
}

export async function scanItem(
  imageDataUrl: string,
  people: Person[],
  items: ClothingItem[],
): Promise<ScanResult> {
  const key = process.env.CLOTHING_GEMINI_API_KEY;
  const output = key ? await callGemini(key, imageDataUrl, people, items) : demoOutput(imageDataUrl, items);

  const category = output.category in CATEGORIES ? output.category : 'other';
  const analysis: ScanAnalysis = {
    category,
    features: output.features,
    size: output.size || undefined,
    colors: output.colors ?? [],
  };
  const item = items[output.match_index];
  const person = item && people.find((p) => p.id === item.personId);
  const confidence = Math.max(0, Math.min(1, Number(output.confidence) || 0));
  const match = item && person
    ? { itemId: item.id, personId: person.id, personName: person.name, confidence, reasoning: output.reasoning }
    : null;
  const confident = !!match && confidence >= MIN_CONFIDENCE;

  return {
    analysis,
    match,
    confident,
    demo: !key,
    verdict: confident
      ? verdictSentence(item!.category, person!.name)
      : match
        ? `לא בטוח — אולי של ${person!.name}`
        : 'לא מצאתי התאמה בספרייה',
  };
}

async function callGemini(key: string, image: string, people: Person[], items: ClothingItem[]): Promise<ModelOutput> {
  const model = process.env.CLOTHING_GEMINI_MODEL || 'gemini-2.5-flash';
  const nameOf = (id: string) => people.find((p) => p.id === id)?.name ?? '?';

  const parts: object[] = [{ text: 'LIBRARY (index · owner · type · size · colours · micro-features):' }];
  let imagesLeft = MAX_REFERENCE_IMAGES;
  // Newest first, so the reference photos sent are the most recently catalogued.
  const order = items.map((it, i) => ({ it, i })).reverse();
  for (const { it, i } of order) {
    parts.push({
      text: `[${i}] · ${nameOf(it.personId)} · ${it.category} · ${it.size ?? '-'} · ${it.colors.join('/')} · ${it.features}`,
    });
    if (it.thumbnail && imagesLeft-- > 0) {
      parts.push({ text: `reference photo of item [${i}]:` }, { inline_data: splitDataUrl(it.thumbnail) });
    }
  }
  if (items.length === 0) parts.push({ text: '(empty — return match_index -1)' });
  parts.push({ text: 'NEW PHOTO to identify:' }, { inline_data: splitDataUrl(image) });

  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
    {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-goog-api-key': key },
      body: JSON.stringify({
        system_instruction: { parts: [{ text: SYSTEM }] },
        contents: [{ role: 'user', parts }],
        generationConfig: {
          temperature: 0.1,
          responseMimeType: 'application/json',
          responseSchema: RESPONSE_SCHEMA,
        },
      }),
      signal: AbortSignal.timeout(60_000),
    },
  );
  if (!res.ok) {
    console.error('Gemini error', res.status, await res.text());
    throw new Error(`vision API ${res.status}`);
  }
  const body = await res.json();
  const text: string | undefined = body?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text) throw new Error('vision API returned no content');
  return JSON.parse(text) as ModelOutput;
}

/**
 * No API key: a deterministic stand-in so the flow can be demonstrated. The UI
 * labels every demo result as such — it is not an identification.
 */
function demoOutput(image: string, items: ClothingItem[]): ModelOutput {
  const h = createHash('sha256').update(image).digest();
  const idx = items.length ? h[0] % items.length : -1;
  const it = items[idx];
  return {
    category: it?.category ?? 'other',
    features: 'מצב הדגמה: לא בוצע ניתוח תמונה אמיתי (לא הוגדר מפתח AI).',
    colors: [],
    match_index: idx,
    confidence: 0.5 + (h[1] / 255) * 0.5,
    reasoning: `בחירה מדומה לצורך הדגמה. תיאור הפריט בספרייה: ${it?.features ?? '—'}`,
  };
}
