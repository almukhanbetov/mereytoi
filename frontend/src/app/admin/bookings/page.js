'use client';

import { useEffect, useState } from 'react';
import { adminApi } from '@/lib/adminApi';
import { formatPrice } from '@/lib/format';

const STATUS_LABELS = {
  new: 'Новая',
  contacted: 'Связались',
  confirmed: 'Подтверждена',
  cancelled: 'Отменена',
};

function formatDate(iso) {
  return new Date(iso).toLocaleString('ru-RU', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' });
}

export default function AdminBookingsPage() {
  const [bookings, setBookings] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  function load() {
    setLoading(true);
    adminApi.bookings()
      .then((d) => setBookings(d.bookings || []))
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }

  useEffect(load, []);

  async function handleStatusChange(id, status) {
    try {
      await adminApi.updateBookingStatus(id, status);
      setBookings((prev) => prev.map((b) => (b.id === id ? { ...b, status } : b)));
    } catch (err) {
      alert(err.message || 'Не удалось обновить статус');
    }
  }

  async function handlePaidToggle(id, paid) {
    try {
      await adminApi.updateBookingPaid(id, paid);
      setBookings((prev) => prev.map((b) => (b.id === id ? { ...b, paid } : b)));
    } catch (err) {
      alert(err.message || 'Не удалось обновить оплату');
    }
  }

  async function handleDelete(id, name) {
    if (!window.confirm(`Удалить заявку от «${name}»?`)) return;
    try {
      await adminApi.deleteBooking(id);
      setBookings((prev) => prev.filter((b) => b.id !== id));
    } catch (err) {
      alert(err.message || 'Не удалось удалить');
    }
  }

  return (
    <div>
      <h1 className="admin-page-title">Заявки</h1>

      {error && <p className="admin-login__error">{error}</p>}
      {loading && <p className="admin-table__empty">Загрузка…</p>}
      {!loading && bookings.length === 0 && <p className="admin-table__empty">Заявок пока нет</p>}

      <div className="booking-list">
        {bookings.map((b) => (
          <div className={`booking-card booking-card--${b.status}`} key={b.id}>
            <div className="booking-card__head">
              <div>
                <p className="booking-card__customer">{b.name}</p>
                <a className="booking-card__phone" href={`tel:${b.phone.replace(/\s/g, '')}`}>{b.phone}</a>
              </div>
              <div className="booking-card__meta">
                <span className="booking-card__date">{formatDate(b.created_at)}</span>
                <label className="booking-card__paid">
                  <input
                    type="checkbox"
                    checked={!!b.paid}
                    onChange={(e) => handlePaidToggle(b.id, e.target.checked)}
                  />
                  Оплачено
                </label>
                <select value={b.status} onChange={(e) => handleStatusChange(b.id, e.target.value)}>
                  {Object.entries(STATUS_LABELS).map(([value, label]) => (
                    <option key={value} value={value}>{label}</option>
                  ))}
                </select>
              </div>
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

            {b.message && <p className="booking-card__message">«{b.message}»</p>}

            <div className="booking-card__footer">
              <span>Итого: <b>{formatPrice(b.total)}</b></span>
              <button className="admin-table__link admin-table__link--danger" onClick={() => handleDelete(b.id, b.name)}>
                Удалить
              </button>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
