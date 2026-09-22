import { addPerson, getLibrary } from '@/lib/db';
import { HttpError, handle, requireUser } from '@/lib/auth';

export const POST = handle(async (req: Request) => {
  const user = await requireUser();
  const { name } = (await req.json().catch(() => ({}))) as { name?: string };
  const clean = String(name ?? '').trim().slice(0, 30);
  if (!clean) throw new HttpError(400, 'יש להזין שם');
  const { people } = await getLibrary(user.id);
  if (people.some((p) => p.name === clean)) throw new HttpError(409, 'השם כבר קיים');
  if (people.length >= 20) throw new HttpError(400, 'אפשר עד 20 בני בית');
  const { ownerId, ...person } = await addPerson(user.id, clean);
  return Response.json({ person });
});
