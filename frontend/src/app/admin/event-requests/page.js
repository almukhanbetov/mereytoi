'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { adminApi } from '@/lib/adminApi';
import { eventTypeLabel, formatEventDate, formatDateTime } from '@/lib/eventHelpers';
import { formatPrice } from '@/lib/format';

const STATUS_LABELS = {
  submitted: 'Отправлена',
  in_review: 'На рассмотрении',
  changes_requested: 'Требуются изменения',
  approved: 'Подтверждена',
  rejected: 'Отклонена',
  cancelled: 'Отменена',
};

const STATUS_CLASS = {
  submitted: 'pending',
  in_review: 'pending',
  changes_requested: 'pending',
  approved: 'paid',
  rejected: 'pending',
  cancelled: 'pending',
};

export default function AdminEventRequestsPage() {
  const [requests, setRequests] = useState([]);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState('all');

  useEffect(() => {
    setLoading(true);
    adminApi.eventRequests(statusFilter)
      .then((d) => setRequests(d.requests || []))
      .finally(() => setLoading(false));
  }, [statusFilter]);

  return (
    <div>
      <h1 className="admin-page-title">Заявки на мероприятия</h1>

      <div className="admin-filters">
        <select value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}>
          <option value="all">Все статусы</option>
          {Object.entries(STATUS_LABELS).map(([value, label]) => (
            <option key={value} value={value}>{label}</option>
          ))}
        </select>
      </div>

      {loading && <p className="admin-table__empty">Загрузка…</p>}
      {!loading && requests.length === 0 && <p className="admin-table__empty">Заявок пока нет</p>}

      <div className="booking-list">
        {requests.map((r) => (
          <Link href={`/admin/event-requests/${r.id}`} className={`booking-card booking-card--${STATUS_CLASS[r.status] || 'pending'}`} key={r.id}>
            <div className="booking-card__head">
              <div>
                <p className="booking-card__customer">{r.event?.title || `Мероприятие #${r.event_id}`}</p>
                <span className="booking-card__phone">
                  {eventTypeLabel(r.event?.type, 'ru')} · {r.event?.city || '—'} · {formatEventDate(r.event?.event_date, 'ru') || 'дата не указана'}
                </span>
              </div>
              <div className="booking-card__meta">
                <span className="booking-card__date">{r.submitted_at ? formatDateTime(r.submitted_at, 'ru') : '—'}</span>
                <span className={`my-booking__status my-booking__status--${STATUS_CLASS[r.status] || 'pending'}`}>
                  {STATUS_LABELS[r.status] || r.status}
                </span>
              </div>
            </div>
            <div className="booking-card__footer">
              <span>Ревизия №{r.latest_revision}</span>
              <span>Итого: <b>{formatPrice(r.total)}</b></span>
            </div>
          </Link>
        ))}
      </div>
    </div>
  );
}
