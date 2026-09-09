'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { T, useLang } from '@/context/AppProviders';
import { useEventWorkspace } from '@/context/EventWorkspaceContext';
import { eventsApi } from '@/lib/eventsApi';
import { fetchCategoriesClient } from '@/lib/catalogApi';
import { formatPrice } from '@/lib/format';
import { daysUntil, activityLine, timeAgo } from '@/lib/eventHelpers';

const QUICK_LINKS = [
  { suffix: '/services', icon: '🎯', ru: 'Услуги', kz: 'Қызметтер' },
  { suffix: '/discussion', icon: '💬', ru: 'Обсуждение', kz: 'Талқылау' },
  { suffix: '/budget', icon: '💰', ru: 'Бюджет', kz: 'Бюджет' },
  { suffix: '/tasks', icon: '✅', ru: 'Задачи', kz: 'Тапсырмалар' },
  { suffix: '/members', icon: '👥', ru: 'Участники', kz: 'Қатысушылар' },
];

export default function EventOverviewPage() {
  const { eventId, event, summary, refreshSummary } = useEventWorkspace();
  const { lang } = useLang();
  const [categories, setCategories] = useState([]);
  const [candidates, setCandidates] = useState([]);
  const [activity, setActivity] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const [cats, cands, feed] = await Promise.all([
        fetchCategoriesClient(),
        eventsApi.candidates(eventId),
        eventsApi.activity(eventId),
      ]);
      if (cancelled) return;
      setCategories(cats);
      setCandidates(cands.candidates || []);
      setActivity(feed.activity || []);
      setLoading(false);
      refreshSummary();
    })();
    return () => { cancelled = true; };
  }, [eventId, refreshSummary]);

  const days = daysUntil(event.event_date);

  const categoryStatus = categories.map((cat) => {
    const inCat = candidates.filter((c) => c.listing?.category_id === cat.id);
    const selected = inCat.find((c) => c.status === 'selected');
    const shortlisted = inCat.filter((c) => c.status !== 'rejected' && c.status !== 'selected');
    return { category: cat, selected, shortlistedCount: shortlisted.length };
  });

  // "Что сделать дальше" — a small, dynamic nudge list; only what's still
  // actually missing shows up, and it disappears entirely once everything
  // is filled in. Date/guests link to the one existing place the event's
  // own fields can be edited today (the budget tab's inline form already
  // round-trips the full event object) — there's no separate "edit event
  // details" page yet, so this reuses what already exists rather than
  // adding new editing UI in this stage.
  const nextSteps = [
    !event.event_date && { key: 'date', icon: '📅', ru: 'Указать дату', kz: 'Күнін көрсету', href: `/profile/events/${eventId}/budget` },
    !event.guests && { key: 'guests', icon: '👥', ru: 'Указать количество гостей', kz: 'Қонақтар санын көрсету', href: `/profile/events/${eventId}/budget` },
    summary && summary.members_count <= 1 && { key: 'invite', icon: '🤝', ru: 'Пригласить близких', kz: 'Жақындарды шақыру', href: `/profile/events/${eventId}/members` },
    candidates.length === 0 && { key: 'services', icon: '🎯', ru: 'Добавить услуги', kz: 'Қызметтер қосу', href: `/profile/events/${eventId}/services` },
    !event.budget_total && { key: 'budget', icon: '💰', ru: 'Указать бюджет', kz: 'Бюджетті көрсету', href: `/profile/events/${eventId}/budget` },
  ].filter(Boolean);

  return (
    <div>
      {summary && (
        <div className="ws-stats" style={{ marginBottom: 34 }}>
          <div className="ws-stat">
            <div className="ws-stat__label"><T ru="До мероприятия" kz="Іс-шараға дейін" /></div>
            <div className="ws-stat__value">{days !== null ? <>{days} <small><T ru="дней" kz="күн" /></small></> : '—'}</div>
          </div>
          <div className="ws-stat">
            <div className="ws-stat__label"><T ru="Бюджет" kz="Бюджет" /></div>
            <div className="ws-stat__value">{formatPrice(summary.spent)} <small>/ {formatPrice(summary.budget_total)}</small></div>
          </div>
          <div className="ws-stat">
            <div className="ws-stat__label"><T ru="Выбрано" kz="Таңдалды" /></div>
            <div className="ws-stat__value">{summary.categories_covered} <small><T ru="из" kz="/" /> {summary.categories_total}</small></div>
          </div>
          <div className="ws-stat">
            <div className="ws-stat__label"><T ru="Команда" kz="Команда" /></div>
            <div className="ws-stat__value">{summary.members_count} <small><T ru="участников" kz="қатысушы" /></small></div>
          </div>
        </div>
      )}

      {nextSteps.length > 0 && (
        <div className="ws-next-steps">
          <h2 className="ws-section-title" style={{ fontSize: 16 }}><T ru="Что сделать дальше" kz="Ары қарай не істеу керек" /></h2>
          <div className="ws-next-steps__list">
            {nextSteps.map((step) => (
              <Link key={step.key} href={step.href} className="ws-next-steps__item">
                <span className="ws-next-steps__icon">{step.icon}</span>
                <span><T ru={step.ru} kz={step.kz} /></span>
                <span className="ws-next-steps__arrow">→</span>
              </Link>
            ))}
          </div>
        </div>
      )}

      <div className="ws-quick-grid">
        {QUICK_LINKS.map((link) => (
          <Link key={link.suffix} href={`/profile/events/${eventId}${link.suffix}`} className="ws-quick-tile">
            <span className="ws-quick-tile__icon">{link.icon}</span>
            <span className="ws-quick-tile__label"><T ru={link.ru} kz={link.kz} /></span>
          </Link>
        ))}
      </div>

      <h2 className="ws-section-title"><T ru="Прогресс организации" kz="Ұйымдастыру барысы" /></h2>

      {loading && <div className="ws-skeleton" style={{ height: 240 }} />}

      {!loading && categoryStatus.length === 0 && (
        <p className="ws-empty__text"><T ru="Категории пока не загружены" kz="Санаттар әлі жүктелмеді" /></p>
      )}

      {!loading && categoryStatus.length > 0 && (
        <div className="ws-cat-progress">
          {categoryStatus.map(({ category, selected, shortlistedCount }) => (
            <div className="ws-cat-row" key={category.id}>
              <span className="ws-cat-row__name">{lang === 'kz' ? category.name_kz : category.name_ru}</span>
              {selected ? (
                <span className="ws-chip ws-chip--gold">✓ {lang === 'kz' ? selected.listing?.name_kz : selected.listing?.name_ru}</span>
              ) : shortlistedCount > 0 ? (
                <Link href={`/profile/events/${eventId}/services`} className="ws-chip">
                  {shortlistedCount} {lang === 'kz' ? 'нұсқа' : 'вариант(а)'}
                </Link>
              ) : (
                <span className="ws-chip ws-chip--outline"><T ru="не выбран" kz="таңдалмаған" /></span>
              )}
            </div>
          ))}
        </div>
      )}

      {!loading && candidates.length === 0 && (
        <div className="ws-empty" style={{ marginTop: 24 }}>
          <span className="ws-empty__icon">🎯</span>
          <h3 className="ws-empty__title"><T ru="Вы ещё ничего не выбрали" kz="Сіз әлі ештеңе таңдаған жоқсыз" /></h3>
          <p className="ws-empty__text">
            <T ru="Добавьте несколько вариантов из каталога, чтобы сравнить их вместе." kz="Бірге салыстыру үшін каталогтан бірнеше нұсқа қосыңыз." />
          </p>
          <Link href="/services" className="btn btn--gold"><T ru="Перейти к услугам" kz="Қызметтерге өту" /></Link>
        </div>
      )}

      {!loading && activity.length > 0 && (
        <>
          <h2 className="ws-section-title" style={{ marginTop: 34 }}><T ru="Активность" kz="Белсенділік" /></h2>
          <div className="ws-thread">
            {activity.slice(0, 12).map((entry) => {
              const { actor, text } = activityLine(entry, lang, formatPrice);
              return (
                <div className="ws-message" key={entry.id}>
                  <div className="ws-avatar">{(actor || '?').slice(0, 2).toUpperCase()}</div>
                  <div className="ws-message__body">
                    <div className="ws-message__head">
                      <span className="ws-message__author">{actor}</span>
                      <span className="ws-message__time">{timeAgo(entry.created_at, lang)}</span>
                    </div>
                    <p className="ws-message__text">{text}</p>
                  </div>
                </div>
              );
            })}
          </div>
        </>
      )}
    </div>
  );
}
