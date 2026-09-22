import { CATEGORIES, addItem, deleteItem, type Category } from '@/lib/db';
import { HttpError, handle, requireUser } from '@/lib/auth';

const MAX_THUMB = 120_000; // characters of data URL (~90 KB)

export const POST = handle(async (req: Request) => {
  const user = await requireUser();
  const b = (await req.json().catch(() => ({}))) as Record<string, unknown>;
  const category = String(b.category) as Category;
  if (!(category in CATEGORIES)) throw new HttpError(400, 'סוג פריט לא תקין');
  const thumbnail = typeof b.thumbnail === 'string' ? b.thumbnail : undefined;
  if (thumbnail && (!thumbnail.startsWith('data:image/jpeg;base64,') || thumbnail.length > MAX_THUMB)) {
    throw new HttpError(400, 'תמונה לא תקינה');
  }
  const item = await addItem(user.id, {
    personId: String(b.personId),
    category,
    features: String(b.features ?? '').slice(0, 500),
    size: b.size ? String(b.size).slice(0, 20) : undefined,
    colors: Array.isArray(b.colors) ? b.colors.map(String).slice(0, 5) : [],
    thumbnail,
  });
  if (!item) throw new HttpError(404, 'בן הבית לא נמצא');
  const { ownerId, ...rest } = item;
  return Response.json({ item: rest });
});

export const DELETE = handle(async (req: Request) => {
  const user = await requireUser();
  const id = new URL(req.url).searchParams.get('id') ?? '';
  if (!(await deleteItem(user.id, id))) throw new HttpError(404, 'הפריט לא נמצא');
  return Response.json({ ok: true });
});
