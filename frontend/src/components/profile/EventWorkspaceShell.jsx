'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { useAuth } from '@/context/AuthContext';
import { T, useLang } from '@/context/AppProviders';
import { EventWorkspaceProvider } from '@/context/EventWorkspaceContext';
import { eventsApi } from '@/lib/eventsApi';
import { eventTypeEmoji, formatEventDate } from '@/lib/eventHelpers';

const TABS = [
  { key: 'overview', icon: '📊', ru: 'Обзор', kz: 'Шолу', en: 'Overview', suffix: '' },
  { key: 'services', icon: '🎯', ru: 'Услуги', kz: 'Қызметтер', en: 'Services', suffix: '/services' },
  { key: 'discussion', icon: '💬', ru: 'Обсуждение', kz: 'Талқылау', en: 'Discussion', suffix: '/discussion' },
  { key: 'budget', icon: '💰', ru: 'Бюджет', kz: 'Бюджет', en: 'Budget', suffix: '/budget' },
  { key: 'request', icon: '📨', ru: 'Заявка', kz: 'Өтінім', en: 'Request', suffix: '/request' },
  { key: 'tasks', icon: '✅', ru: 'Задачи', kz: 'Тапсырмалар', en: 'Tasks', suffix: '/tasks' },
  { key: 'members', icon: '👥', ru: 'Участники', kz: 'Қатысушылар', en: 'Members', suffix: '/members' },
];
// Mobile keeps only the four the brief calls out explicitly; the rest live
// behind "Ещё" so the bar never gets cramped on a phone.
const MOBILE_PRIMARY = ['overview', 'services', 'discussion', 'budget'];

function WorkspaceSkeleton() {
  return (
    <section className="ws-hero">
      <div className="container">
        <div className="ws-skeleton" style={{ height: 28, width: 260, marginBottom: 14 }} />
        <div className="ws-skeleton" style={{ height: 16, width: 380, marginBottom: 28 }} />
        <div className="ws-stats">
          {[0, 1, 2, 3].map((i) => <div key={i} className="ws-skeleton" style={{ height: 76 }} />)}
        </div>
      </div>
    </section>
  );
}

export default function EventWorkspaceShell({ eventId, children }) {
  const { isAuthenticated, loading: authLoading } = useAuth();
  const { lang } = useLang();
  const router = useRouter();
  const pathname = usePathname();

  const [state, setState] = useState({ status: 'loading' });
  const [moreOpen, setMoreOpen] = useState(false);

  useEffect(() => {
    if (authLoading) return;
    if (!isAuthenticated) {
      router.replace(`/login?next=/profile/events/${eventId}`);
      return;
    }
    let cancelled = false;
    (async () => {
      try {
        const data = await eventsApi.get(eventId);
        if (cancelled) return;
        setState({ status: 'ready', event: data.event, myRole: data.my_role });
      } catch {
        if (!cancelled) setState({ status: 'error' });
      }
    })();
    return () => { cancelled = true; };
  }, [eventId, isAuthenticated, authLoading, router]);

  if (authLoading || state.status === 'loading') return <WorkspaceSkeleton />;

  if (state.status === 'error') {
    return (
      <section style={{ padding: '160px 0 100px' }}>
        <div className="container">
          <div className="ws-empty">
            <span className="ws-empty__icon">🔒</span>
            <h2 className="ws-empty__title"><T ru="Мероприятие не найдено" kz="Іс-шара табылмады" /></h2>
            <p className="ws-empty__text">
              <T ru="Либо оно не существует, либо у вас нет к нему доступа." kz="Ол жоқ немесе сізде оған қол жеткізу құқығы жоқ." />
            </p>
            <Link href="/profile" className="btn btn--outline"><T ru="К моим мероприятиям" kz="Іс-шараларыма" /></Link>
          </div>
        </div>
      </section>
    );
  }

  const { event, myRole } = state;
  const dateLabel = formatEventDate(event.event_date, lang);
  const base = `/profile/events/${eventId}`;
  const activeTab = TABS.find((tab) => (tab.suffix ? pathname === base + tab.suffix : pathname === base)) || TABS[0];

  return (
    <EventWorkspaceProvider eventId={Number(eventId)} event={event} myRole={myRole} summary={null}>
      <section className="ws-hero">
        <div className="container">
          <Link href="/profile" className="ws-hero__back">← <T ru="Мои мероприятия" kz="Менің іс-шараларым" /></Link>
          <h1 className="ws-hero__title">{eventTypeEmoji(event.type)} {event.title}</h1>
          <p className="ws-hero__meta">
            {dateLabel && <span>📅 <b>{dateLabel}</b></span>}
            {event.city && <span>📍 {event.city}</span>}
            {event.guests > 0 && <span>👥 {event.guests} <T ru="гостей" kz="қонақ" /></span>}
          </p>
        </div>
      </section>

      <div className="container">
        <div className="ws-shell">
          <nav className="ws-sidebar">
            {TABS.map((tab) => (
              <Link
                key={tab.key}
                href={base + tab.suffix}
                className={`ws-sidebar__link${tab.key === activeTab.key ? ' is-active' : ''}`}
                aria-current={tab.key === activeTab.key ? 'page' : undefined}
              >
                <span className="ws-sidebar__icon">{tab.icon}</span>
                <T ru={tab.ru} kz={tab.kz} en={tab.en} />
              </Link>
            ))}
          </nav>

          <div className="ws-content">{children}</div>
        </div>
      </div>

      <nav className="ws-bottomnav">
        <div className="ws-bottomnav__row">
          {TABS.filter((tab) => MOBILE_PRIMARY.includes(tab.key)).map((tab) => (
            <Link
              key={tab.key}
              href={base + tab.suffix}
              className={`ws-bottomnav__link${tab.key === activeTab.key ? ' is-active' : ''}`}
              aria-current={tab.key === activeTab.key ? 'page' : undefined}
            >
              <span className="ws-bottomnav__icon">{tab.icon}</span>
              <T ru={tab.ru} kz={tab.kz} en={tab.en} />
            </Link>
          ))}
          <button
            type="button"
            className={`ws-bottomnav__link${['request', 'tasks', 'members'].includes(activeTab.key) ? ' is-active' : ''}`}
            aria-expanded={moreOpen}
            onClick={() => setMoreOpen(true)}
          >
            <span className="ws-bottomnav__icon">•••</span>
            <T ru="Ещё" kz="Тағы" />
          </button>
        </div>
      </nav>

      {moreOpen && (
        <div className="ws-modal-overlay" onClick={() => setMoreOpen(false)}>
          <div className="ws-modal" onClick={(e) => e.stopPropagation()}>
            <div className="ws-modal__head">
              <h3 className="ws-modal__title"><T ru="Ещё" kz="Тағы" /></h3>
              <button type="button" className="admin-table__link" onClick={() => setMoreOpen(false)}>✕</button>
            </div>
            {TABS.filter((tab) => !MOBILE_PRIMARY.includes(tab.key)).map((tab) => (
              <Link
                key={tab.key}
                href={base + tab.suffix}
                className="ws-sidebar__link"
                style={{ marginBottom: 4 }}
                onClick={() => setMoreOpen(false)}
              >
                <span className="ws-sidebar__icon">{tab.icon}</span>
                <T ru={tab.ru} kz={tab.kz} en={tab.en} />
              </Link>
            ))}
          </div>
        </div>
      )}
    </EventWorkspaceProvider>
  );
}
