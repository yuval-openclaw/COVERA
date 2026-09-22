'use client';

import { useEffect, useRef, useState } from 'react';
import { Icon } from './Icon';
import { ApiError, CATEGORY_UI, api, resizeImage, type Item, type Person, type ScanResult } from '@/lib/client';

type Stage =
  | { name: 'choose' }
  | { name: 'camera' }
  | { name: 'analyzing'; image: string }
  | { name: 'result'; image: string; result: ScanResult }
  | { name: 'error'; image?: string; message: string };

const STEPS = ['מזהה את סוג הפריט…', 'בודק מידה ותוויות…', 'מחפש קרעים, כתמים ושחיקה…', 'משווה לספרייה…'];

export function ScanFlow({
  people, onClose, onSaved, onUnauthorized,
}: {
  people: Person[];
  onClose: () => void;
  onSaved: (item: Item) => void;
  onUnauthorized: () => void;
}) {
  const [stage, setStage] = useState<Stage>({ name: 'choose' });
  const [closing, setClosing] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);
  const captureRef = useRef<HTMLInputElement>(null);

  const close = () => { setClosing(true); setTimeout(onClose, 220); };

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && close();
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  });

  async function analyze(image: string) {
    setStage({ name: 'analyzing', image });
    try {
      // A floor on the wait so the analysis state reads as a step, not a flicker.
      const [result] = await Promise.all([
        api<ScanResult>('/api/scan', { body: { image } }),
        new Promise((r) => setTimeout(r, 1400)),
      ]);
      setStage({ name: 'result', image, result });
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) return onUnauthorized();
      setStage({ name: 'error', image, message: e instanceof Error ? e.message : 'שגיאה' });
    }
  }

  async function onFile(file?: File) {
    if (!file) return;
    try {
      analyze(await resizeImage(file, 1024));
    } catch {
      setStage({ name: 'error', message: 'לא הצלחנו לקרוא את התמונה. נסו קובץ JPG או PNG.' });
    }
  }

  function openCamera() {
    // Live preview where supported; otherwise the OS camera via the capture input.
    if (typeof navigator.mediaDevices?.getUserMedia === 'function') setStage({ name: 'camera' });
    else captureRef.current?.click();
  }

  return (
    <div className={`sheet-wrap ${closing ? 'out' : ''}`} role="dialog" aria-modal="true" aria-label="סריקת פריט">
      <div className="sheet">
        <header className="sheet-head">
          <h2>סריקת פריט</h2>
          <button className="icon-btn" onClick={close} aria-label="סגירה"><Icon name="close" size={18} /></button>
        </header>

        <input ref={fileRef} type="file" accept="image/*" hidden onChange={(e) => onFile(e.target.files?.[0])} />
        <input ref={captureRef} type="file" accept="image/*" capture="environment" hidden
          onChange={(e) => onFile(e.target.files?.[0])} />

        <div className="stage" key={stage.name}>
          {stage.name === 'choose' && (
            <div className="choose">
              <p>צלמו פריט אחד, פרוש על משטח חלק.</p>
              <button className="option main" onClick={openCamera}>
                <span className="ic"><Icon name="camera" size={26} /></span>
                <span><b>צילום</b><small>פתיחת המצלמה</small></span>
              </button>
              <button className="option" onClick={() => fileRef.current?.click()}>
                <span className="ic"><Icon name="image" size={26} /></span>
                <span><b>העלאה מהגלריה</b><small>תמונה קיימת מהמכשיר</small></span>
              </button>
              <div className="tips" aria-label="טיפים">
                <span>אור טוב</span><span>קרוב לתווית המידה</span><span>קרעים וכתמים בפריים</span>
              </div>
            </div>
          )}

          {stage.name === 'camera' && (
            <Camera
              onCapture={(img) => analyze(img)}
              onFail={() => setStage({ name: 'error', message: 'אין גישה למצלמה. אפשר לאשר גישה בהגדרות הדפדפן, או להעלות תמונה.' })}
            />
          )}

          {stage.name === 'analyzing' && <Analyzing image={stage.image} />}

          {stage.name === 'result' && (
            <Result
              image={stage.image}
              result={stage.result}
              people={people}
              onAgain={() => setStage({ name: 'choose' })}
              onSaved={(item) => { onSaved(item); close(); }}
              onUnauthorized={onUnauthorized}
            />
          )}

          {stage.name === 'error' && (
            <div className="center-col">
              {stage.image && <img className="preview small" src={stage.image} alt="" />}
              <p className="error" role="alert">{stage.message}</p>
              {stage.image && <button className="btn primary block" onClick={() => analyze(stage.image!)}>ניסיון נוסף</button>}
              <button className="btn ghost block" onClick={() => setStage({ name: 'choose' })}>בחירת תמונה אחרת</button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function Camera({ onCapture, onFail }: { onCapture: (img: string) => void; onFail: () => void }) {
  const video = useRef<HTMLVideoElement>(null);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    let stream: MediaStream | undefined;
    let cancelled = false;
    navigator.mediaDevices
      .getUserMedia({ video: { facingMode: { ideal: 'environment' }, width: { ideal: 1920 } }, audio: false })
      .then((s) => {
        if (cancelled) return s.getTracks().forEach((t) => t.stop());
        stream = s;
        if (video.current) video.current.srcObject = s;
      })
      .catch(onFail);
    return () => { cancelled = true; stream?.getTracks().forEach((t) => t.stop()); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function shoot() {
    const v = video.current;
    if (!v || !v.videoWidth) return;
    const c = document.createElement('canvas');
    c.width = v.videoWidth;
    c.height = v.videoHeight;
    c.getContext('2d')!.drawImage(v, 0, 0);
    onCapture(await resizeImage(c, 1024));
  }

  return (
    <div className="camera">
      <div className="viewfinder">
        <video ref={video} autoPlay playsInline muted onLoadedData={() => setReady(true)} />
        <div className="frame" aria-hidden />
        {!ready && <div className="spinner" aria-label="פותח מצלמה" />}
      </div>
      <button className="shutter" onClick={shoot} disabled={!ready} aria-label="צילום" />
    </div>
  );
}

function Analyzing({ image }: { image: string }) {
  const [step, setStep] = useState(0);
  useEffect(() => {
    const t = setInterval(() => setStep((s) => Math.min(s + 1, STEPS.length - 1)), 1600);
    return () => clearInterval(t);
  }, []);
  return (
    <div className="center-col" aria-live="polite" aria-busy="true">
      <div className="scan-frame">
        <img className="preview" src={image} alt="הפריט שנסרק" />
        <div className="scan-line" aria-hidden />
        <div className="scan-grid" aria-hidden />
      </div>
      <ol className="steps">
        {STEPS.map((s, i) => (
          <li key={s} className={i < step ? 'done' : i === step ? 'now' : ''}>{s}</li>
        ))}
      </ol>
    </div>
  );
}

function Result({
  image, result, people, onAgain, onSaved, onUnauthorized,
}: {
  image: string; result: ScanResult; people: Person[];
  onAgain: () => void; onSaved: (item: Item) => void; onUnauthorized: () => void;
}) {
  const { analysis, match, confident, verdict, demo } = result;
  const owner = match && people.find((p) => p.id === match.personId);
  const [personId, setPersonId] = useState(match?.personId ?? people[0]?.id ?? '');
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState('');
  const pct = match ? Math.round(match.confidence * 100) : 0;

  async function save() {
    setSaving(true);
    setErr('');
    try {
      const { item } = await api<{ item: Item }>('/api/items', {
        body: {
          personId,
          category: analysis.category,
          features: analysis.features,
          size: analysis.size,
          colors: analysis.colors,
          thumbnail: await shrink(image),
        },
      });
      onSaved(item);
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) return onUnauthorized();
      setErr(e instanceof Error ? e.message : 'שגיאה');
      setSaving(false);
    }
  }

  return (
    <div className="result">
      {demo && <p className="note" role="note">מצב הדגמה: לא הוגדר מפתח AI, והתוצאה מדומה.</p>}
      <div className="verdict-card" style={{ '--tint': owner?.color ?? 'var(--line)' } as React.CSSProperties}>
        <img src={image} alt="" />
        <div className="verdict-body">
          <p className="eyebrow">
            {CATEGORY_UI[analysis.category].he}{analysis.size ? ` · מידה ${analysis.size}` : ''}
            {analysis.colors.length > 0 && ` · ${analysis.colors.join(', ')}`}
          </p>
          <h3 className={confident ? 'verdict' : 'verdict unsure'}>{verdict}</h3>
          {match && (
            <div className="meter" aria-label={`רמת ביטחון ${pct}%`}>
              <div className="bar"><span style={{ width: `${pct}%` }} /></div>
              <span>ביטחון {pct}%</span>
            </div>
          )}
          <div className="detail">
            <h4>מה זוהה</h4>
            <p>{analysis.features}</p>
          </div>
          {match?.reasoning && (
            <div className="detail">
              <h4>למה</h4>
              <p>{match.reasoning}</p>
            </div>
          )}
        </div>
      </div>

      {people.length > 0 && (
        <div className="detail">
          <h4>{confident ? 'שמירה בספרייה' : 'של מי הפריט? שמירה תשפר את הזיהוי הבא'}</h4>
          <div className="owner-pick tabs" role="radiogroup">
            {people.map((p) => (
              <button key={p.id} role="radio" aria-checked={personId === p.id}
                className={`tab ${personId === p.id ? 'on' : ''}`}
                style={{ '--tint': p.color } as React.CSSProperties}
                onClick={() => setPersonId(p.id)}>
                <span className="sw" />{p.name}
              </button>
            ))}
          </div>
          {err && <p className="error" role="alert">{err}</p>}
          <button className="btn primary block" onClick={save} disabled={saving || !personId}>
            {saving ? 'שומר…' : `שמירה אצל ${people.find((p) => p.id === personId)?.name ?? ''}`}
          </button>
        </div>
      )}
      <button className="btn ghost block" onClick={onAgain}>סריקת פריט נוסף</button>
    </div>
  );
}

async function shrink(dataUrl: string) {
  const blob = await (await fetch(dataUrl)).blob();
  return resizeImage(blob, 320, 0.7);
}
