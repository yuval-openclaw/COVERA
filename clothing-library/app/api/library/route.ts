import { getLibrary } from '@/lib/db';
import { handle, requireUser } from '@/lib/auth';

export const GET = handle(async () => {
  const user = await requireUser();
  const { people, items } = await getLibrary(user.id);
  return Response.json({
    people: people.map(({ ownerId, ...p }) => p),
    items: items.map(({ ownerId, ...i }) => i),
  });
});
