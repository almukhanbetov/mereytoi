'use client';

import { use, useEffect, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/context/AuthContext';
import { T, useLang } from '@/context/AppProviders';
import { eventsApi } from '@/lib/eventsApi';
import { eventTypeEmoji, eventTypeLabel, formatEventDate, roleLabel } from '@/lib/eventHelpers';

export default function InvitePage({ params }) {
  const { token } = use(params);
  const { user, isAuthenticated, loading: authLoading } = useAuth();
  const { lang } = useLang();
  const router = useRouter();

  const [state, setState] = useState({ status: 'loading' });
  const [accepting, setAccepting] = useState(false);

  useEffect(() => {
    let cancelled = false;
    eventsApi.previewInvitation(token)
      .then((data) => { if (!cancelled) setState({ status: 'ready', preview: data }); })
      .catch((err) => { if (!cancelled) setState({ status: 'error', message: err.message }); });
    return () => { cancelled = true; };
  }, [token]);

  async function handleAccept() {
    setAccepting(true);
    try {
      const result = await eventsApi.acceptInvitation(token);
      router.push(`/profile/events/${result.event_id}`);
    } catch (err) {
      alert(err.message);
      setAccepting(false);
    }
  }

  return (
    <section className="page-hero" style={{ padding: '150px 0 120px', minHeight: '70vh' }}>
      <div className="hero__blob hero__blob--1"></div>
      <div className="container" style={{ maxWidth: 520 }}>
        {state.status === 'loading' && <div className="ws-skeleton" style={{ height: 220 }} />}

        {state.status === 'error' && (
          <div className="ws-empty">
            <span className="ws-empty__icon">🚫</span>
            <h2 className="ws-empty__title"><T ru="Приглашение недействительно" kz="Шақыру жарамсыз" /></h2>
            <p className="ws-empty__text">
              <T ru="Ссылка отозвана или больше не активна." kz="Сілтеме кері қайтарылған немесе енді белсенді емес." />
            </p>
            <Link href="/" className="btn btn--outline"><T ru="На главную" kz="Басты бетке" /></Link>
          </div>
        )}

        {state.status === 'ready' && (
          <div className="ws-event-card" style={{ padding: 36, textAlign: 'center' }}>
            <span style={{ fontSize: 40 }}>{eventTypeEmoji(state.preview.event.type)}</span>
            <p style={{ color: 'var(--text-muted)', margin: '18px 0 6px' }}>
              <b style={{ color: 'var(--text)' }}>{state.preview.inviter_name}</b>{' '}
              <T ru="приглашает вас помочь с организацией:" kz="сізді ұйымдастыруға көмектесуге шақырады:" />
            </p>
            <h1 style={{ fontFamily: 'var(--font-playfair), serif', fontSize: 26, margin: '0 0 10px' }}>{state.preview.event.title}</h1>
            <p style={{ color: 'var(--text-muted)', marginBottom: 8 }}>
              {eventTypeLabel(state.preview.event.type, lang)}
              {state.preview.event.event_date && ` · ${formatEventDate(state.preview.event.event_date, lang)}`}
              {state.preview.event.city && ` · ${state.preview.event.city}`}
            </p>
            <p style={{ marginBottom: 28 }}>
              <span className="ws-chip ws-chip--gold"><T ru="Роль:" kz="Рөлі:" /> {roleLabel(state.preview.role, lang)}</span>
            </p>

            {authLoading ? null : isAuthenticated ? (
              <button type="button" className="btn btn--gold btn--block" onClick={handleAccept} disabled={accepting}>
                {accepting ? <T ru="Присоединяемся…" kz="Қосылуда…" /> : <T ru="Открыть планирование →" kz="Жоспарлауды ашу →" />}
              </button>
            ) : (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                <p style={{ fontSize: 13.5, color: 'var(--text-muted)' }}>
                  <T ru="Войдите или зарегистрируйтесь, чтобы принять приглашение." kz="Шақыруды қабылдау үшін кіріңіз немесе тіркеліңіз." />
                </p>
                <Link href={`/login?next=/invite/${token}`} className="btn btn--gold btn--block"><T ru="Войти" kz="Кіру" /></Link>
                <Link href={`/register?next=/invite/${token}`} className="btn btn--outline btn--block"><T ru="Зарегистрироваться" kz="Тіркелу" /></Link>
              </div>
            )}
          </div>
        )}
      </div>
    </section>
  );
}
