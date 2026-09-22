'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { AccessCodeModal } from '@/components/AccessCodeModal';
import { ScanFlow } from '@/components/ScanFlow';
import { Icon } from '@/components/Icon';
import {
  ApiError, CATEGORY_UI, api, copyText, type Category, type Item, type Person, type User,
} from '@/lib/client';

export default function LibraryPage() {
  const router = useRouter();
  const [user, setUser] = useState<User | null>(null);
  const [people, setPeople] = useState<Person[] | null>(null);
  const [items, setItems] = useState<Item[]>([]);
  const [filter, setFilter] = useState<string>('all');
  const [category, setCategory] = useState<Category | 'all'>('all');
  const [scanning, setScanning] = useState(false);
  const [adding, setAdding] = useState(false);
  const [menu, setMenu] = useState(false);
  const [toast, setToast] = useState('');
  const [error, setError] = useState('');

  const signedOut = useCallback(() => router.replace('/'), [router]);

  useEffect(() => {
    (async () => {
      try {
        const { user } = await api<{ user: User | null }>('/api/auth');
        if (!user) return signedOut();
        setUser(user);
        const lib = await api<{ people: Person[]; items: Item[] }>('/api/library');
        setPeople(lib.people);
        setItems(lib.items);
      } catch (e) {
        if (e instanceof ApiError && e.status === 401) return signedOut();
        setError('לא הצלחנו לטעון את הספרייה. בדקו את החיבור ורעננו.');
      }
    })();
  }, [signedOut]);

  const toastTimer = useRef<ReturnType<typeof setTimeout>>(undefined);
  const flash = (msg: string) => {
    clearTimeout(toastTimer.current);
    setToast(msg);
    toastTimer.current = setTimeout(() => setToast(''), 2400);
  };

  const visiblePeople = useMemo(
    () => (people ?? []).filter((p) => filter === 'all' || p.id === filter),
    [people, filter],
  );

  async function removeItem(item: Item) {
    try {
      await api(`/api/items?id=${encodeURIComponent(item.id)}`, { method: 'DELETE' });
      setItems((xs) => xs.filter((x) => x.id !== item.id));
      flash('הפריט נמחק');
    } catch (e) {
      flash(e instanceof Error ? e.message : 'שגיאה');
    }
  }

  async function signOut() {
    await api('/api/auth', { body: { action: 'signout' } }).catch(() => {});
    router.replace('/');
  }

  if (error) return <main className="page"><p className="error" role="alert">{error}</p></main>;
  if (!user || !people) return <main className="page"><LibrarySkeleton /></main>;

  const categoriesPresent = [...new Set(items.map((i) => i.category))];
  const hasPeople = people.length > 0;

  return (
    <main className="page">
      <header className="masthead">
        <div>
          <p className="eyebrow">{user.kind === 'guest' ? 'מצב אורח' : user.email}</p>
          <h1>הספרייה</h1>
          {hasPeople && (
            <p className="summary">
              <span><b>{people.length}</b>בני בית</span>
              <span><b>{items.length}</b>פריטים</span>
            </p>
          )}
        </div>
        <button className="icon-btn" onClick={() => setMenu((m) => !m)} aria-expanded={menu} aria-label="חשבון">
          <Icon name="more" size={20} />
        </button>
        {menu && (
          <div className="menu fade-in" role="menu">
            <p className="eyebrow">קוד הגישה שלכם</p>
            <button className="code-box small" role="menuitem"
              onClick={async () => { if (await copyText(user.accessCode)) flash('הקוד הועתק'); }}>
              <span dir="ltr">{user.accessCode}</span>
              <Icon name="copy" size={18} />
            </button>
            <button className="btn ghost block" role="menuitem" onClick={signOut}>
              <Icon name="logout" size={18} /> התנתקות
            </button>
          </div>
        )}
      </header>

      {!hasPeople ? (
        <section className="onboard">
          <h2>נתחיל מהבית</h2>
          <p>הספרייה ריקה. שלושה צעדים והיא תדע לזהות של מי כל פריט.</p>
          <ol className="steps-list">
            <li><span className="num">1</span><div><b>הוסיפו את בני הבית</b><small>כל מי שהכביסה שלו עוברת פה</small></div></li>
            <li><span className="num">2</span><div><b>סרקו פריטים ושייכו אותם</b><small>קרוב לתוויות, לקרעים ולכתמים</small></div></li>
            <li><span className="num">3</span><div><b>מהפעם הבאה — זיהוי אוטומטי</b><small>מצלמים, ומקבלים תשובה</small></div></li>
          </ol>
          <button className="btn primary block" onClick={() => setAdding(true)}>
            <Icon name="plus" size={20} /> הוספת בן בית
          </button>
        </section>
      ) : (
        <>
          <nav className="tabs" aria-label="סינון לפי בן בית">
            <button className={`tab ${filter === 'all' ? 'on' : ''}`} onClick={() => setFilter('all')}>
              כולם <span className="n">{items.length}</span>
            </button>
            {people.map((p) => (
              <button key={p.id} className={`tab ${filter === p.id ? 'on' : ''}`}
                style={{ '--tint': p.color } as React.CSSProperties}
                onClick={() => setFilter(p.id)}>
                <span className="sw" />{p.name} <span className="n">{items.filter((i) => i.personId === p.id).length}</span>
              </button>
            ))}
            <button className="tab add" onClick={() => setAdding(true)}>
              <Icon name="plus" size={16} /> בן בית
            </button>
          </nav>

          {categoriesPresent.length > 1 && (
            <nav className="tabs types" aria-label="סינון לפי סוג">
              <button className={`tab ${category === 'all' ? 'on' : ''}`} onClick={() => setCategory('all')}>כל הסוגים</button>
              {categoriesPresent.map((c) => (
                <button key={c} className={`tab ${category === c ? 'on' : ''}`} onClick={() => setCategory(c)}>
                  <Icon name={c} size={16} /> {CATEGORY_UI[c].he}
                </button>
              ))}
            </nav>
          )}

          {visiblePeople.map((p, idx) => {
            const own = items
              .filter((i) => i.personId === p.id && (category === 'all' || i.category === category))
              .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
            return (
              <section key={p.id} className="shelf" style={{ '--tint': p.color, animationDelay: `${idx * 60}ms` } as React.CSSProperties}>
                <div className="shelf-head">
                  <span className="avatar" aria-hidden>{p.name.slice(0, 1)}</span>
                  <h2>{p.name}</h2>
                  <span className="count">{own.length} פריטים</span>
                </div>
                {own.length === 0 ? (
                  <button className="shelf-empty" onClick={() => setScanning(true)}>
                    <Icon name="camera" size={20} /> סריקת הפריט הראשון של {p.name}
                  </button>
                ) : (
                  <ul className="tiles">
                    {own.map((it) => <ItemCard key={it.id} item={it} onDelete={() => removeItem(it)} />)}
                  </ul>
                )}
              </section>
            );
          })}
        </>
      )}

      {hasPeople && (
        <button className="scan-fab" onClick={() => setScanning(true)}>
          <Icon name="camera" size={24} /> סריקת פריט
        </button>
      )}

      {scanning && (
        <ScanFlow
          people={people}
          onClose={() => setScanning(false)}
          onUnauthorized={signedOut}
          onSaved={(item) => {
            setItems((xs) => [...xs, item]);
            flash(`נשמר בספרייה של ${people.find((p) => p.id === item.personId)?.name}`);
          }}
        />
      )}

      {adding && (
        <AddPersonSheet
          onClose={() => setAdding(false)}
          onUnauthorized={signedOut}
          onAdded={(person) => {
            setPeople((ps) => [...(ps ?? []), person]);
            flash(`${person.name} נוסף/ה`);
          }}
        />
      )}

      <AccessCodeModal userId={user.id} code={user.accessCode} />
      {toast && <div className="toast" role="status">{toast}</div>}
    </main>
  );
}

/** Two-tap delete: the first tap arms it, so a stray tap never deletes. */
function ItemCard({ item, onDelete }: { item: Item; onDelete: () => void }) {
  const [armed, setArmed] = useState(false);
  useEffect(() => {
    if (!armed) return;
    const t = setTimeout(() => setArmed(false), 3000);
    return () => clearTimeout(t);
  }, [armed]);
  const ui = CATEGORY_UI[item.category];
  return (
    <li className="tile">
      <div className="tile-img">
        {item.thumbnail ? <img src={item.thumbnail} alt="" loading="lazy" /> : <Icon name={item.category} size={44} stroke={1.2} />}
      </div>
      <div className="tile-body">
        <div className="tile-title">
          {ui.he}
          {item.size && <span className="size" dir="ltr">{item.size}</span>}
        </div>
        <p>{item.features}</p>
      </div>
      <button className={`tile-del ${armed ? 'armed' : ''}`}
        onClick={() => (armed ? onDelete() : setArmed(true))}
        aria-label={armed ? 'לחצו שוב למחיקה' : 'מחיקת פריט'}>
        {armed ? 'למחוק?' : <Icon name="trash" size={16} />}
      </button>
    </li>
  );
}

function AddPersonSheet({
  onClose, onAdded, onUnauthorized,
}: { onClose: () => void; onAdded: (p: Person) => void; onUnauthorized: () => void }) {
  const [name, setName] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState('');
  const [closing, setClosing] = useState(false);
  const input = useRef<HTMLInputElement>(null);

  useEffect(() => { input.current?.focus(); }, []);
  const close = () => { setClosing(true); setTimeout(onClose, 220); };

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    const clean = name.trim();
    if (!clean) return setErr('יש להזין שם');
    setBusy(true);
    setErr('');
    try {
      const { person } = await api<{ person: Person }>('/api/people', { body: { name: clean } });
      onAdded(person);
      close();
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) return onUnauthorized();
      setErr(e instanceof Error ? e.message : 'שגיאה');
      setBusy(false);
    }
  }

  return (
    <div className={`sheet-wrap ${closing ? 'out' : ''}`} role="dialog" aria-modal="true" aria-labelledby="add-title"
      onClick={(e) => e.target === e.currentTarget && close()}>
      <form className="sheet compact" onSubmit={submit}>
        <header className="sheet-head">
          <h2 id="add-title">בן בית חדש</h2>
          <button type="button" className="icon-btn" onClick={close} aria-label="סגירה"><Icon name="close" size={18} /></button>
        </header>
        <label className="field">
          שם
          <input ref={input} value={name} maxLength={30} placeholder="למשל: אייל"
            onChange={(e) => { setName(e.target.value); setErr(''); }}
            onKeyDown={(e) => {
              // Explicit, so Enter works even where implicit form submission does not fire.
              if (e.key === 'Enter' && !e.nativeEvent.isComposing) { e.preventDefault(); e.currentTarget.form?.requestSubmit(); }
              if (e.key === 'Escape') close();
            }} />
        </label>
        {err && <p className="error" role="alert">{err}</p>}
        <button className="btn primary block" disabled={busy}>
          {busy ? 'מוסיף…' : 'הוספה'}
        </button>
      </form>
    </div>
  );
}

function LibrarySkeleton() {
  return (
    <div aria-busy="true" aria-label="טוען">
      <div className="skel" style={{ width: '55%', height: 44, margin: '28px 0 30px' }} />
      {[0, 1].map((i) => (
        <div key={i} style={{ marginBottom: 28 }}>
          <div className="skel" style={{ width: '30%', height: 22, marginBottom: 12 }} />
          <div className="skel" style={{ height: 84, marginBottom: 8 }} />
        </div>
      ))}
    </div>
  );
}
