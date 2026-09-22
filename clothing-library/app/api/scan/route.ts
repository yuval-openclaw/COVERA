import { getLibrary } from '@/lib/db';
import { HttpError, handle, requireUser } from '@/lib/auth';
import { scanItem } from '@/lib/vision';
import { limit } from '@/lib/limits';

export const maxDuration = 60;
const MAX_IMAGE = 3_000_000; // characters of data URL; the client sends ~1024px JPEGs

export const POST = handle(async (req: Request) => {
  const user = await requireUser();
  limit(`scan:${user.id}`, 40, 3600_000, 'הגעתם למגבלת הסריקות לשעה. נסו שוב מאוחר יותר.');
  const { image } = (await req.json().catch(() => ({}))) as { image?: string };
  if (typeof image !== 'string' || !/^data:image\/(jpeg|png|webp);base64,/.test(image) || image.length > MAX_IMAGE) {
    throw new HttpError(400, 'התמונה לא תקינה או גדולה מדי');
  }
  const { people, items } = await getLibrary(user.id);
  try {
    return Response.json(await scanItem(image, people, items));
  } catch (err) {
    console.error(err);
    throw new HttpError(502, 'שירות הזיהוי לא זמין כרגע, נסו שוב');
  }
});
