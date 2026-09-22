import * as db from '@/lib/db';
import {
  HttpError, currentUser, endSession, handle, hashPassword, newAccessCode, startSession, verifyPassword,
} from '@/lib/auth';
import { clientIp, limit } from '@/lib/limits';

// In-memory throttle for password and code guesses (per process; fine for a mock).
const attempts = new Map<string, { n: number; until: number }>();
function throttle(key: string) {
  const a = attempts.get(key);
  if (a && a.until > Date.now() && a.n >= 8) throw new HttpError(429, 'יותר מדי ניסיונות, נסו שוב בעוד כמה דקות');
  attempts.set(key, a && a.until > Date.now() ? { ...a, n: a.n + 1 } : { n: 1, until: Date.now() + 10 * 60_000 });
}

const publicUser = (u: db.User) => ({ id: u.id, kind: u.kind, email: u.email, accessCode: u.accessCode });

export const GET = handle(async () => {
  const user = await currentUser();
  return Response.json({ user: user ? publicUser(user) : null });
});

export const POST = handle(async (req: Request) => {
  const body = (await req.json().catch(() => ({}))) as Record<string, string>;
  const ip = clientIp(req);

  switch (body.action) {
    case 'signup': {
      limit(`signup:${ip}`, 10, 3600_000, 'יותר מדי הרשמות מהרשת הזו. נסו שוב בעוד שעה.');
      const email = String(body.email ?? '').trim().toLowerCase();
      const password = String(body.password ?? '');
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) throw new HttpError(400, 'כתובת אימייל לא תקינה');
      if (password.length < 8) throw new HttpError(400, 'הסיסמה צריכה לכלול לפחות 8 תווים');
      if (await db.findUserByEmail(email)) throw new HttpError(409, 'כבר קיים חשבון עם האימייל הזה');
      const user = await db.createUser({
        kind: 'account', email, passwordHash: await hashPassword(password), accessCode: await newAccessCode(),
      });
      await startSession(user.id);
      return Response.json({ user: publicUser(user), fresh: true });
    }
    case 'signin': {
      throttle(`pw:${ip}`);
      const user = await db.findUserByEmail(String(body.email ?? '').trim());
      const ok = user?.passwordHash && (await verifyPassword(String(body.password ?? ''), user.passwordHash));
      if (!user || !ok) throw new HttpError(401, 'אימייל או סיסמה שגויים');
      await startSession(user.id);
      return Response.json({ user: publicUser(user), fresh: false });
    }
    case 'guest': {
      limit(`guest:${ip}`, 10, 3600_000, 'נוצרו יותר מדי חשבונות אורח מהרשת הזו. נסו שוב בעוד שעה.');
      const user = await db.createUser({ kind: 'guest', accessCode: await newAccessCode() });
      await startSession(user.id);
      return Response.json({ user: publicUser(user), fresh: true });
    }
    case 'code': {
      throttle(`code:${ip}`);
      const user = await db.findUserByAccessCode(String(body.code ?? ''));
      if (!user) throw new HttpError(401, 'קוד גישה לא נמצא');
      await startSession(user.id);
      return Response.json({ user: publicUser(user), fresh: false });
    }
    case 'signout':
      await endSession();
      return Response.json({ ok: true });
    default:
      throw new HttpError(400, 'פעולה לא מוכרת');
  }
});
