'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { Icon } from '@/components/Icon';
import { api, writePromptState, type User } from '@/lib/client';

type Mode = null | 'signin' | 'signup' | 'code';

export default function Landing() {
  const router = useRouter();
  const [mode, setMode] = useState<Mode>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [form, setForm] = useState({ email: '', password: '', code: '' });

  // Already signed in → straight to the library.
  useEffect(() => {
    api<{ user: User | null }>('/api/auth').then((r) => r.user && router.replace('/library')).catch(() => {});
  }, [router]);

  async function submit(action: 'signin' | 'signup' | 'guest' | 'code') {
    setBusy(true);
    setError('');
    try {
      const { user } = await api<{ user: User }>('/api/auth', { body: { action, ...form } });
      // Whoever typed the code in already has it saved.
      if (action === 'code') writePromptState(user.id, { copied: true });
      router.push('/library');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'שגיאה');
      setBusy(false);
    }
  }

  const set = (k: keyof typeof form) => (e: React.ChangeEvent<HTMLInputElement>) =>
    setForm({ ...form, [k]: e.target.value });

  return (
    <main className="landing">
      <div className="brand">
        <span className="brand-mark"><Icon name="shirt" size={18} /></span>
        ספריית בגדים
      </div>

      {mode === null ? (
        <>
          <section className="hero fade-in">
            <div className="tags" aria-hidden>
              <TagCard name="אייל" tint="#A9C4E4" item="גרב · קרע בעקב" />
              <TagCard name="דבורה" tint="#E9B8A2" item="מכנס פשתן · מידה M" />
              <TagCard name="יובל" tint="#E7D39B" item="טישרט · כתם בצווארון" />
            </div>
            <h1>של מי <em>הגרב</em> הזאת?</h1>
            <p className="lead">מצלמים פריט מהכביסה, והמערכת מזהה למי הוא שייך לפי הפרטים הקטנים: מידה, קרעים, כתמים ושחיקה.</p>
          </section>
          <div className="actions fade-in">
            <div className="row">
              <button className="btn primary" onClick={() => setMode('signup')}>הרשמה</button>
              <button className="btn secondary" onClick={() => setMode('signin')}>התחברות</button>
            </div>
            <button className="btn ghost block" onClick={() => submit('guest')} disabled={busy}>
              {busy ? 'פותח ספרייה…' : 'המשך כאורח'}
            </button>
            <div className="sub">
              <button className="link" onClick={() => setMode('code')}>יש לי קוד גישה</button>
            </div>
            {error && <p className="error" role="alert">{error}</p>}
          </div>
        </>
      ) : (
        <form
          className="form hero fade-in"
          key={mode}
          onSubmit={(e) => { e.preventDefault(); submit(mode); }}
        >
          <div className="form-head">
            <button type="button" className="icon-btn" aria-label="חזרה"
              onClick={() => { setMode(null); setError(''); }}>
              <Icon name="arrow" size={20} />
            </button>
          </div>
          <h2>{mode === 'signin' ? 'ברוכים השבים' : mode === 'signup' ? 'יצירת חשבון' : 'כניסה עם קוד'}</h2>
          {mode === 'code' ? (
            <label className="field">
              קוד גישה
              <input dir="ltr" value={form.code} onChange={set('code')} placeholder="CL-XXXX-XXXX"
                autoCapitalize="characters" autoComplete="off" required autoFocus />
            </label>
          ) : (
            <>
              <label className="field">
                אימייל
                <input dir="ltr" type="email" value={form.email} onChange={set('email')}
                  autoComplete="email" required autoFocus />
              </label>
              <label className="field">
                סיסמה
                <input dir="ltr" type="password" value={form.password} onChange={set('password')}
                  autoComplete={mode === 'signup' ? 'new-password' : 'current-password'}
                  minLength={mode === 'signup' ? 8 : undefined} required />
                {mode === 'signup' && <small>לפחות 8 תווים</small>}
              </label>
            </>
          )}
          {error && <p className="error" role="alert">{error}</p>}
          <button className="btn primary block" disabled={busy}>
            {busy ? 'רגע…' : mode === 'signup' ? 'יצירת חשבון' : 'כניסה'}
          </button>
        </form>
      )}
    </main>
  );
}

function TagCard({ name, tint, item }: { name: string; tint: string; item: string }) {
  return (
    <div className="tag-card" style={{ '--tint': tint } as React.CSSProperties}>
      <span className="eyebrow">שייך ל־</span>
      <div className="who"><span className="sw">{name[0]}</span>{name}</div>
      <small>{item}</small>
    </div>
  );
}
