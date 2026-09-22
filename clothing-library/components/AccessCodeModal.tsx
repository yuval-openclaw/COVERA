'use client';

import { useEffect, useState } from 'react';
import { Icon } from './Icon';
import { copyText, readPromptState, writePromptState } from '@/lib/client';

/**
 * Urges the user to copy their access code. Ignored once → shown one more time
 * with stronger wording. Ignored twice → never shown again for this user.
 * Copying ends it for good as well.
 */
export function AccessCodeModal({ userId, code }: { userId: string; code: string }) {
  const [round, setRound] = useState<0 | 1 | 2>(0); // 0 hidden, 1 first ask, 2 last ask
  const [copied, setCopied] = useState(false);
  const [closing, setClosing] = useState(false);

  useEffect(() => {
    const s = readPromptState(userId);
    if (s.copied || (s.dismissals ?? 0) >= 2) return;
    const t = setTimeout(() => setRound(s.dismissals === 1 ? 2 : 1), 450);
    return () => clearTimeout(t);
  }, [userId]);

  if (!round) return null;

  const close = (next: () => void) => {
    setClosing(true);
    setTimeout(() => { setClosing(false); next(); }, 220);
  };

  const onCopy = async () => {
    if (!(await copyText(code))) return;
    setCopied(true);
    writePromptState(userId, { copied: true });
    setTimeout(() => close(() => setRound(0)), 900);
  };

  const onSkip = () => {
    const dismissals = round;
    writePromptState(userId, { dismissals });
    close(() => {
      if (dismissals === 1) setTimeout(() => setRound(2), 350);
      else setRound(0);
    });
  };

  const last = round === 2;
  return (
    <div className={`overlay ${closing ? 'out' : ''}`} role="presentation">
      <div className="dialog" role="dialog" aria-modal="true" aria-labelledby="code-title" key={round}>
        <div className={`dialog-icon ${last ? 'warn' : ''}`}><Icon name="key" /></div>
        <h2 id="code-title">{last ? 'רגע, בלי הקוד אי אפשר לחזור' : 'שמרו את קוד הגישה שלכם'}</h2>
        <p className="muted">
          {last
            ? 'זו הפעם האחרונה שנציג את החלון. בלי הקוד לא תוכלו לפתוח את הספרייה ממכשיר אחר, ואורחים לא יוכלו לחזור אליה בכלל.'
            : 'הקוד פותח את ספריית הבגדים שלכם מכל מכשיר. העתיקו אותו ושמרו במקום בטוח.'}
        </p>
        <button className="code-box" onClick={onCopy} aria-label={`העתקת הקוד ${code}`}>
          <span dir="ltr">{code}</span>
          <Icon name="copy" size={20} />
        </button>
        <button className="btn primary block" onClick={onCopy} disabled={copied}>
          {copied ? 'הועתק' : 'העתקת הקוד'}
        </button>
        <button className="btn ghost block" onClick={onSkip}>
          {last ? 'המשך בלי לשמור' : 'אחר כך'}
        </button>
      </div>
    </div>
  );
}
