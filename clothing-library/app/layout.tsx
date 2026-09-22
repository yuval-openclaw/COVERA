import type { Metadata, Viewport } from 'next';
import { Frank_Ruhl_Libre, Rubik } from 'next/font/google';
import './globals.css';

const rubik = Rubik({ subsets: ['hebrew', 'latin'], variable: '--font' });
const frank = Frank_Ruhl_Libre({ subsets: ['hebrew', 'latin'], weight: ['500', '700'], variable: '--font-display' });

export const metadata: Metadata = {
  title: 'ספריית בגדים',
  description: 'זיהוי של מי כל פריט לבוש, לפי סימנים קטנים: מידה, קרעים, כתמים ושחיקה.',
};

export const viewport: Viewport = {
  width: 'device-width',
  initialScale: 1,
  viewportFit: 'cover',
  themeColor: [
    { media: '(prefers-color-scheme: light)', color: '#f5f2ec' },
    { media: '(prefers-color-scheme: dark)', color: '#0f0f0e' },
  ],
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="he" dir="rtl" className={`${rubik.variable} ${frank.variable}`}>
      <body>{children}</body>
    </html>
  );
}
