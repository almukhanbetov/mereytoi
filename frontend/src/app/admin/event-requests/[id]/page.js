'use client';

import { use, useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { adminApi } from '@/lib/adminApi';
import { eventTypeLabel, formatEventDate, formatDateTime, roleLabel } from '@/lib/eventHelpers';
import { formatPrice } from '@/lib/format';

const STATUS_LABELS = {
  draft: 'Черновик',
  submitted: 'Отправлена',
  in_review: 'На рассмотрении',
  changes_requested: 'Требуются изменения',
  approved: 'Подтверждена',
  rejected: 'Отклонена',
  cancelled: 'Отменена',
};

// Mirrors models.CanTransition on the backend — the backend is still the
// real authority (it re-validates every call), this is purely so the admin
// only ever sees buttons for moves that will actually succeed.
const NEXT_STATUSES = {
  submitted: ['in_review', 'changes_requested', 'approved', 'rejected'],
  in_review: ['changes_requested', 'approved', 'rejected'],
};

export default function AdminEventRequestDetailPage({ params }) {
  const { id } = use(params);
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [managerComment, setManagerComment] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [savedNotice, setSavedNotice] = useState('');

  const load = useCallback(() => {
    adminApi.eventRequest(id)
      .then((d) => { setData(d); setManagerComment(d.request.manager_comment || ''); })
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }, [id]);

  useEffect(load, [load]);

  async function handleStatusChange(nextStatus) {
    setSaving(true);
    setError('');
    setSavedNotice('');
    try {
      await adminApi.updateEventRequestStatus(id, nextStatus, managerComment);
      setSavedNotice(`Статус обновлён: ${STATUS_LABELS[nextStatus]}`);
      load();
    } catch (err) {
      setError(err.message || 'Не удалось изменить статус');
    } finally {
      setSaving(false);
    }
  }

  if (loading) return <p className="admin-table__empty">Загрузка…</p>;
  if (!data) return <p className="admin-table__empty">Заявка не найдена</p>;

  const { request, event, members, revisions } = data;
  const latest = revisions[0];
  const snapshot = latest?.snapshot;
  const nextStatuses = NEXT_STATUSES[request.status] || [];

  return (
    <div>
      <Link href="/admin/event-requests" className="admin-table__link">← Все заявки</Link>
      <h1 className="admin-page-title">{event.title}</h1>
      <p className="admin-table__empty" style={{ margin: '0 0 20px', textAlign: 'left' }}>
        {eventTypeLabel(event.type, 'ru')} · {event.city || '—'} · {event.guests || 0} гостей · {formatEventDate(event.event_date, 'ru') || 'дата не указана'}
      </p>

      <div className="admin-stat-card" style={{ display: 'inline-block', marginBottom: 30 }}>
        <div className="admin-stat-card__label">Статус заявки</div>
        <div className="admin-stat-card__num" style={{ fontSize: 20 }}>{STATUS_LABELS[request.status] || request.status}</div>
      </div>

      <h2 className="admin-section-title">Команда</h2>
      <div className="admin-table-wrap">
        <table className="admin-table">
          <thead><tr><th>Имя</th><th>Email</th><th>Роль</th></tr></thead>
          <tbody>
            {members.map((m) => (
              <tr key={m.id}>
                <td>{m.user?.name}</td>
                <td>{m.user?.email}</td>
                <td>{roleLabel(m.role, 'ru')}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <h2 className="admin-section-title">
        Выбранные услуги {latest && `(ревизия №${latest.revision_number})`}
      </h2>
      {snapshot?.items?.length > 0 ? (
        <div className="booking-list">
          <div className="booking-card">
            <div className="booking-card__items">
              {snapshot.items.map((it, i) => (
                <div className="booking-card__item" key={i}>
                  <div>
                    <span className="booking-card__item-name">{it.name}</span>
                    {it.category_name && <span className="booking-card__item-cat"> · {it.category_name}</span>}
                  </div>
                  <span className="booking-card__item-price">{formatPrice(it.price)}</span>
                </div>
              ))}
            </div>
            <div className="booking-card__footer">
              <span>Итого: <b>{formatPrice(snapshot.total)}</b></span>
            </div>
          </div>
        </div>
      ) : (
        <p className="admin-table__empty">Нет выбранных услуг в этой ревизии</p>
      )}

      {snapshot?.organizer_comment && (
        <>
          <h2 className="admin-section-title">Комментарий организатора</h2>
          <p className="booking-card__message">«{snapshot.organizer_comment}»</p>
        </>
      )}

      <h2 className="admin-section-title">История ревизий</h2>
      <div className="admin-table-wrap">
        <table className="admin-table">
          <thead><tr><th>№</th><th>Отправлена</th><th>Кем</th><th>Сумма</th></tr></thead>
          <tbody>
            {revisions.map((rev) => (
              <tr key={rev.id}>
                <td>{rev.revision_number}</td>
                <td>{formatDateTime(rev.submitted_at, 'ru')}</td>
                <td>{rev.submitted_by?.name}</td>
                <td>{formatPrice(rev.total)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <h2 className="admin-section-title">Решение</h2>
      <label style={{ display: 'block', marginBottom: 14 }}>
        <span style={{ display: 'block', fontSize: 13, color: 'var(--text-muted)', fontWeight: 600, marginBottom: 8 }}>
          Комментарий менеджеру (виден организатору)
        </span>
        <textarea
          value={managerComment}
          onChange={(e) => setManagerComment(e.target.value)}
          rows={3}
          style={{ width: '100%', maxWidth: 560, padding: '12px 16px', borderRadius: 10, border: '1px solid var(--border)', background: 'var(--input-bg)', color: 'var(--text)', fontFamily: 'inherit', fontSize: 14 }}
        />
      </label>

      {error && <p className="admin-login__error">{error}</p>}
      {savedNotice && <p className="form-success is-visible">{savedNotice}</p>}

      {nextStatuses.length > 0 ? (
        <div style={{ display: 'flex', gap: 10, marginTop: 10, flexWrap: 'wrap' }}>
          {nextStatuses.map((s) => (
            <button
              key={s}
              type="button"
              className={s === 'approved' ? 'btn btn--gold' : 'btn btn--outline'}
              style={{ padding: '10px 18px', fontSize: 13.5 }}
              onClick={() => handleStatusChange(s)}
              disabled={saving}
            >
              {STATUS_LABELS[s]}
            </button>
          ))}
        </div>
      ) : (
        <p className="admin-table__empty">Решение по этой заявке уже принято — статус финальный.</p>
      )}
    </div>
  );
}
