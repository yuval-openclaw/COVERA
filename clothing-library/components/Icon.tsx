import type { Category } from '@/lib/client';

const PATHS = {
  camera: 'M4 8h3l1.5-2h7L17 8h3v11H4z M12 17a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7z',
  image: 'M4 5h16v14H4z M4 16l5-5 4 4 2-2 5 5 M15.5 9.5h.01',
  plus: 'M12 5v14 M5 12h14',
  close: 'M6 6l12 12 M18 6L6 18',
  more: 'M5 12h.01 M12 12h.01 M19 12h.01',
  trash: 'M5 7h14 M10 7V5h4v2 M7 7l1 12h8l1-12',
  key: 'M14.5 9.5a4 4 0 1 1-.01 0z M11.5 12.5L4 20 M6 18l2 2 M8 16l2 2',
  copy: 'M9 9h10v10H9z M5 15V5h10',
  arrow: 'M19 12H5 M11 6l-6 6 6 6',
  logout: 'M15 4h4v16h-4 M10 8l-4 4 4 4 M6 12h10',
  // garments
  shirt: 'M8 4l-5 3 2 4 3-1v10h8V10l3 1 2-4-5-3c-.5 1.5-2 2.5-4 2.5S8.5 5.5 8 4z',
  pants: 'M7 3h10l1 18h-4l-2-11-2 11H6z M7 6h10',
  socks: 'M9 3h6v9l-.5 1c2 1 4 2.2 4 4.5A3.5 3.5 0 0 1 15 21H10a4 4 0 0 1-3-6.5L9 12z M9 6h6',
  underwear: 'M3 7h18v3c-3 .5-6 3-7 8h-4c-1-5-4-7.5-7-8z',
  dress: 'M9 3h6l-1 4 4 14H6l4-14z M10 7h4',
  sweater: 'M8 4h8l5 4-1 8-3-1v6H7v-6l-3 1-1-8z M9 4c.5 1.5 1.5 2 3 2s2.5-.5 3-2',
  other: 'M4 9h16l-2 11H6z M9 9V7a3 3 0 0 1 6 0v2',
} as const;

export type IconName = keyof typeof PATHS;

export function Icon({ name, size = 22, stroke = 1.6 }: { name: IconName | Category; size?: number; stroke?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor"
      strokeWidth={name === 'more' ? 3 : stroke} strokeLinecap="round" strokeLinejoin="round" aria-hidden
      className="icon">
      <path d={PATHS[name]} />
    </svg>
  );
}
