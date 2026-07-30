'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/context/AuthContext';
import { T, useLang } from '@/context/AppProviders';
import { authApi } from '@/lib/authApi';
import { formatPrice } from '@/lib/format';

const STATUS_LABELS = {
  new: { ru: 'Новая', kz: 'Жаңа' },
  contacted: { ru: 'Связались', kz: 'Хабарластық' },
  confirmed: { ru: 'Подтверждена', kz: 'Расталды' },
  cancelled: { ru: 'Отменена', kz: 'Болдырылмады' },
};

function formatDate(iso) {
  return new Date(iso).toLocaleDateString('ru-RU', { day: '2-digit', month: '2-digit', year: 'numeric' });
}

export default function ProfilePage() {
  const { user, loading, isAuthenticated, logout, updateProfile } = useAuth();
  const { lang } = useLang();
  const router = useRouter();

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
    authApi.myBookings()
      .then((d) => setBookings(d.bookings || []))
      .finally(() => setBookingsLoading(false));
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

  if (loading || !isAuthenticated) {
    return <div className="auth-page"><p className="admin-table__empty">Загрузка…</p></div>;
  }

  return (
    <>
      <section className="page-hero" style={{ padding: '150px 0 60px' }}>
        <div className="hero__blob hero__blob--1"></div>
        <div className="hero__blob hero__blob--2"></div>
        <div className="container">
          <h1><T ru="Мой профиль" kz="Жеке кабинетім" /></h1>
          <p><T ru="Ваши данные и история заявок" kz="Деректеріңіз бен өтінімдер тарихы" /></p>
        </div>
      </section>

      <section style={{ padding: '20px 0 120px' }}>
        <div className="container" style={{ display: 'grid', gridTemplateColumns: '1fr 1.4fr', gap: 50, alignItems: 'start' }}>
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
                <div className={`booking-card booking-card--${b.status}`} key={b.id}>
                  <div className="booking-card__head">
                    <span className="booking-card__date">{formatDate(b.created_at)}</span>
                    <span className={`my-booking__status my-booking__status--${b.status}`}>
                      {STATUS_LABELS[b.status]?.[lang] || b.status}
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
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </section>
    </>
  );
}
