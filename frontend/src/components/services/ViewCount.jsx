'use client';

import { useLang } from '@/context/AppProviders';
import { formatCount } from '@/lib/format';

const LABEL = { ru: 'Просмотров', kz: 'Қаралым', en: 'Views' };

/** The eye icon and a listing's view total, as stored by the API. */
export default function ViewCount({ count = 0, className = '' }) {
  const { lang } = useLang();
  const label = `${LABEL[lang] || LABEL.ru}: ${formatCount(count)}`;
  return (
    <span className={`view-count ${className}`.trim()} title={label} aria-label={label} data-testid="view-count">
      <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
        <path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7-10-7-10-7Z" />
        <circle cx="12" cy="12" r="3" />
      </svg>
      <span aria-hidden="true">{formatCount(count)}</span>
    </span>
  );
}
