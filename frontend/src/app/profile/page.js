'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { useAuth } from '@/context/AuthContext';
import { T, useLang } from '@/context/AppProviders';
import { authApi } from '@/lib/authApi';
import { eventsApi } from '@/lib/eventsApi';
import { formatPrice } from '@/lib/format';
import { eventTypeEmoji, eventTypeLabel, formatEventDate, roleLabel } from '@/lib/eventHelpers';

function paidLabel(paid, lang) {
  if (paid) return lang === 'kz' ? 'Белсенді' : 'Активна';
  return lang === 'kz' ? 'Қарастырылуда' : 'На рассмотрении';
}

function formatDate(iso) {
  return new Date(iso).toLocaleDateString('ru-RU', { day: '2-digit', month: '2-digit', year: 'numeric' });
}

export default function ProfilePage() {
  const { user, loading, isAuthenticated, logout, updateProfile } = useAuth();
  const { lang } = useLang();
  const router = useRouter();

  const [tab, setTab] = useState('events');

  const [events, setEvents] = useState([]);
  const [eventsLoading, setEventsLoading] = useState(true);

  const [name, setName] = useState('');
  const [phone, setPhone] = useState('');
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState('');

  const [bookings, setBookings] = useState([]);
  const [bookingsLoading, setBookingsLoading] = useState(true);

  useEffect(() => {
    if (!loading && !isAuthenticated) router.replace('/login');
  }, [loading, isAuthenticated, router]);

  useEffect(() => {
    if (user) {
      setName(user.name || '');
      setPhone(user.phone || '');
    }
  }, [user]);

  useEffect(() => {
    if (!isAuthenticated) return;
    eventsApi.list().then((d) => setEvents(d.events || [])).finally(() => setEventsLoading(false));
    authApi.myBookings().then((d) => setBookings(d.bookings || [])).finally(() => setBookingsLoading(false));
  }, [isAuthenticated]);

  async function handleSave(e) {
    e.preventDefault();
    setError('');
    setSaving(true);
    try {
      await updateProfile(name, phone);
      setSaved(true);
      setTimeout(() => setSaved(false), 2200);
    } catch (err) {
      setError(err.message || 'Не удалось сохранить');
    } finally {
      setSaving(false);
    }
  }

  function handleLogout() {
    logout();
    router.push('/');
  }

  async function handleDeleteBooking(id) {
    const confirmText = lang === 'kz' ? 'Өтінімді жоюды растайсыз ба?' : 'Удалить эту заявку?';
    if (!window.confirm(confirmText)) return;
    try {
      await authApi.deleteMyBooking(id);
      setBookings((prev) => prev.filter((b) => b.id !== id));
    } catch (err) {
      alert(err.message || (lang === 'kz' ? 'Жою сәтсіз аяқталды' : 'Не удалось удалить'));
    }
  }

  if (loading || !isAuthenticated) {
    return <div className="auth-page"><p className="admin-table__empty">Загрузка…</p></div>;
  }

  return (
    <>
      <section className="page-hero" style={{ padding: '150px 0 40px' }}>
        <div className="hero__blob hero__blob--1"></div>
        <div className="hero__blob hero__blob--2"></div>
        <div className="container">
          <h1><T ru="Мой той" kz="Менің тойым" /></h1>
          <p><T ru="Ваше пространство для совместной организации мероприятий" kz="Іс-шараларды бірге ұйымдастыруға арналған кеңістігіңіз" /></p>
        </div>
      </section>

      <section style={{ padding: '0 0 120px' }}>
        <div className="container">
          <div className="ws-tabs">
            <button type="button" className={`ws-tabs__btn${tab === 'events' ? ' is-active' : ''}`} onClick={() => setTab('events')}>
              <T ru="Мои мероприятия" kz="Менің іс-шараларым" />
            </button>
            <button type="button" className={`ws-tabs__btn${tab === 'account' ? ' is-active' : ''}`} onClick={() => setTab('account')}>
              <T ru="Аккаунт" kz="Аккаунт" />
            </button>
          </div>

          {tab === 'events' && (
            <>
              <div className="ws-events-head">
                <h2 className="admin-section-title" style={{ margin: 0 }}><T ru="Мероприятия" kz="Іс-шаралар" /></h2>
                <Link href="/profile/events/new" className="btn btn--gold" style={{ padding: '12px 24px' }}>
                  + <T ru="Создать мероприятие" kz="Іс-шара құру" />
                </Link>
              </div>

              {eventsLoading && (
                <div className="ws-events-grid">
                  {[0, 1, 2].map((i) => <div key={i} className="ws-skeleton" style={{ height: 180 }} />)}
                </div>
              )}

              {!eventsLoading && events.length === 0 && (
                <div className="ws-empty">
                  <span className="ws-empty__icon">🎉</span>
                  <h3 className="ws-empty__title"><T ru="У вас пока нет мероприятия" kz="Сізде әлі іс-шара жоқ" /></h3>
                  <p className="ws-empty__text">
                    <T ru="Создайте свой первый той и пригласите близких помогать с выбором." kz="Алғашқы тойыңызды құрып, жақындарыңызды таңдауға көмектесуге шақырыңыз." />
                  </p>
                  <Link href="/profile/events/new" className="btn btn--gold"><T ru="Создать мероприятие" kz="Іс-шара құру" /></Link>
                </div>
              )}

              {!eventsLoading && events.length > 0 && (
                <div className="ws-events-grid">
                  {events.map((ev) => (
                    <Link href={`/profile/events/${ev.id}`} className="ws-event-card" key={ev.id}>
                      <span className="ws-event-card__type">{eventTypeEmoji(ev.type)} {eventTypeLabel(ev.type, lang)}</span>
                      <h3 className="ws-event-card__title">{ev.title}</h3>
                      <p className="ws-event-card__meta">
                        {ev.event_date && <span>📅 {formatEventDate(ev.event_date, lang)}</span>}
                        {ev.city && <span>📍 {ev.city}</span>}
                        {ev.guests > 0 && <span>👥 {ev.guests}</span>}
                      </p>
                      <div className="ws-event-card__footer">
                        <span className="ws-chip ws-chip--gold">{roleLabel(ev.my_role, lang)}</span>
                        {ev.budget_total > 0 && <span style={{ fontWeight: 700, color: 'var(--gold-light)' }}>{formatPrice(ev.budget_total)}</span>}
                      </div>
                    </Link>
                  ))}
                  <Link href="/profile/events/new" className="ws-create-card">
                    <span className="ws-create-card__icon">+</span>
                    <T ru="Новое мероприятие" kz="Жаңа іс-шара" />
                  </Link>
                </div>
              )}
            </>
          )}

          {tab === 'account' && (
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1.4fr', gap: 50, alignItems: 'start' }}>
              <form className="contacts__form" onSubmit={handleSave}>
                <label>
                  <span><T ru="Ваше имя" kz="Атыңыз" /></span>
                  <input type="text" value={name} onChange={(e) => setName(e.target.value)} required />
                </label>
                <label>
                  <span>Email</span>
                  <input type="email" value={user?.email || ''} disabled />
                </label>
                <label>
                  <span><T ru="Телефон" kz="Телефон" /></span>
                  <input type="tel" value={phone} onChange={(e) => setPhone(e.target.value)} placeholder="+7 700 000 00 00" />
                </label>

                {error && <p className="auth-card__error">{error}</p>}

                <button type="submit" className="btn btn--gold" disabled={saving}>
                  {saving ? <T ru="Сохраняем…" kz="Сақталуда…" /> : <T ru="Сохранить" kz="Сақтау" />}
                </button>
                <p className={`form-success${saved ? ' is-visible' : ''}`}>
                  <T ru="Изменения сохранены" kz="Өзгерістер сақталды" />
                </p>

                <button type="button" className="btn btn--outline" style={{ marginTop: 8 }} onClick={handleLogout}>
                  <T ru="Выйти из аккаунта" kz="Аккаунттан шығу" />
                </button>
              </form>

              <div>
                <h2 className="admin-section-title" style={{ marginTop: 0 }}>
                  <T ru="История заявок" kz="Өтінімдер тарихы" />
                </h2>

                {bookingsLoading && <p className="admin-table__empty">Загрузка…</p>}
                {!bookingsLoading && bookings.length === 0 && (
                  <p className="admin-table__empty"><T ru="Заявок пока нет" kz="Әзірге өтінімдер жоқ" /></p>
                )}

                <div className="booking-list">
                  {bookings.map((b) => (
                    <div className={`booking-card booking-card--${b.paid ? 'paid' : 'pending'}`} key={b.id}>
                      <div className="booking-card__head">
                        <span className="booking-card__date">{formatDate(b.created_at)}</span>
                        <span className={`my-booking__status my-booking__status--${b.paid ? 'paid' : 'pending'}`}>
                          {paidLabel(b.paid, lang)}
                        </span>
                      </div>
                      <div className="booking-card__items">
                        {(b.items || []).map((item, i) => (
                          <div className="booking-card__item" key={i}>
                            <div>
                              <span className="booking-card__item-name">{item.name}</span>
                              {item.category && <span className="booking-card__item-cat"> · {item.category}</span>}
                              {item.guests > 0 && (
                                <div className="booking-card__item-guests">{item.guests} чел. × {formatPrice(item.unit_price)}</div>
                              )}
                            </div>
                            <span className="booking-card__item-price">{formatPrice(item.total_price)}</span>
                          </div>
                        ))}
                      </div>
                      <div className="booking-card__footer">
                        <span><T ru="Итого" kz="Барлығы" />: <b>{formatPrice(b.total)}</b></span>
                        <button
                          type="button"
                          className="admin-table__link admin-table__link--danger"
                          onClick={() => handleDeleteBooking(b.id)}
                        >
                          <T ru="Удалить" kz="Жою" />
                        </button>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          )}
        </div>
      </section>
    </>
  );
}
