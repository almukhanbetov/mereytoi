'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { useAuth } from '@/context/AuthContext';
import { T, useLang } from '@/context/AppProviders';
import { eventsApi } from '@/lib/eventsApi';
import { EVENT_TYPES, eventTypeLabel, eventTypeEmoji } from '@/lib/eventHelpers';

export default function NewEventPage() {
  const { isAuthenticated, loading: authLoading } = useAuth();
  const { lang } = useLang();
  const router = useRouter();

  const [title, setTitle] = useState('');
  const [type, setType] = useState('wedding');
  const [date, setDate] = useState('');
  const [city, setCity] = useState('');
  const [guests, setGuests] = useState('');
  const [budget, setBudget] = useState('');
  const [comment, setComment] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    if (!authLoading && !isAuthenticated) router.replace('/login?next=/profile/events/new');
  }, [authLoading, isAuthenticated, router]);

  async function handleSubmit(e) {
    e.preventDefault();
    setError('');
    if (!title.trim()) return;
    setSaving(true);
    try {
      const { event } = await eventsApi.create({
        title: title.trim(),
        type,
        event_date: date || null,
        city: city.trim(),
        guests: Number(guests) || 0,
        budget_total: Number(budget) || 0,
        comment: comment.trim(),
      });
      router.push(`/profile/events/${event.id}`);
    } catch (err) {
      setError(err.message || (lang === 'kz' ? 'Іс-шара құрылмады' : 'Не удалось создать мероприятие'));
    } finally {
      setSaving(false);
    }
  }

  if (authLoading || !isAuthenticated) return null;

  return (
    <section className="page-hero" style={{ padding: '150px 0 100px' }}>
      <div className="hero__blob hero__blob--1"></div>
      <div className="container" style={{ maxWidth: 640 }}>
        <p className="breadcrumb">
          <Link href="/profile"><T ru="Мой той" kz="Менің тойым" /></Link>
          <span>/</span>
          <span className="is-current"><T ru="Создать мероприятие" kz="Іс-шара құру" /></span>
        </p>
        <h1><T ru="Создать мероприятие" kz="Іс-шара құру" /></h1>
        <p style={{ color: 'var(--text-muted)', marginBottom: 36 }}>
          <T
            ru="Получите отдельное пространство, чтобы вместе с близкими выбирать услуги, обсуждать и следить за бюджетом."
            kz="Жақындарыңызбен бірге қызметтерді таңдау, талқылау және бюджетті бақылау үшін жеке кеңістік алыңыз."
          />
        </p>

        <form className="ws-form contacts__form" onSubmit={handleSubmit}>
          <label>
            <span><T ru="Название" kz="Атауы" /></span>
            <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder={lang === 'kz' ? 'Мысалы, «Мұхтар мен Айжан тойы»' : 'Например, «Свадьба Мухтара и Айжан»'} required />
          </label>

          <label>
            <span><T ru="Тип мероприятия" kz="Іс-шара түрі" /></span>
            <div className="ws-type-grid">
              {EVENT_TYPES.map((t) => (
                <button
                  key={t}
                  type="button"
                  aria-pressed={type === t}
                  className={`ws-type-option${type === t ? ' is-selected' : ''}`}
                  onClick={() => setType(t)}
                >
                  <span className="ws-type-option__emoji">{eventTypeEmoji(t)}</span>
                  {eventTypeLabel(t, lang)}
                </button>
              ))}
            </div>
          </label>

          <div className="ws-form__row">
            <label>
              <span><T ru="Дата" kz="Күні" /></span>
              <input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
            </label>
            <label>
              <span><T ru="Город" kz="Қала" /></span>
              <input value={city} onChange={(e) => setCity(e.target.value)} placeholder="Алматы" />
            </label>
          </div>

          <div className="ws-form__row">
            <label>
              <span><T ru="Гостей (примерно)" kz="Қонақтар саны (шамамен)" /></span>
              <input type="number" min="0" value={guests} onChange={(e) => setGuests(e.target.value)} placeholder="150" />
            </label>
            <label>
              <span><T ru="Бюджет, ₸ (ориентировочно)" kz="Бюджет, ₸ (болжалды)" /></span>
              <input type="number" min="0" value={budget} onChange={(e) => setBudget(e.target.value)} placeholder="3 000 000" />
            </label>
          </div>

          <label>
            <span><T ru="Комментарий" kz="Пікір" /></span>
            <textarea rows={3} value={comment} onChange={(e) => setComment(e.target.value)} placeholder={lang === 'kz' ? 'Қосымша ақпарат' : 'Дополнительные пожелания'} />
          </label>

          {error && <p className="auth-card__error">{error}</p>}

          <button type="submit" className="btn btn--gold" disabled={saving || !title.trim()}>
            {saving ? <T ru="Создаём…" kz="Құрылуда…" /> : <T ru="Создать мероприятие" kz="Іс-шараны құру" />}
          </button>
        </form>
      </div>
    </section>
  );
}
