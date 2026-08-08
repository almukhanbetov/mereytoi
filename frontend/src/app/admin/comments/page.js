'use client';

import { useEffect, useMemo, useState } from 'react';
import { adminApi } from '@/lib/adminApi';

function formatDate(iso) {
  return new Date(iso).toLocaleString('ru-RU', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' });
}

function Stars({ value }) {
  return (
    <span style={{ color: 'var(--gold)', letterSpacing: 2 }}>
      {'★'.repeat(value)}
      <span style={{ color: 'var(--border)' }}>{'★'.repeat(5 - value)}</span>
    </span>
  );
}

export default function AdminCommentsPage() {
  const [comments, setComments] = useState([]);
  const [listings, setListings] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [filter, setFilter] = useState('pending');

  const listingById = useMemo(() => {
    const map = new Map();
    listings.forEach((l) => map.set(l.id, l));
    return map;
  }, [listings]);

  function load() {
    setLoading(true);
    const approved = filter === 'all' ? undefined : filter === 'approved';
    Promise.all([adminApi.comments(approved), adminApi.listings()])
      .then(([c, l]) => {
        setComments(c.comments || []);
        setListings(l.listings || []);
      })
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }

  useEffect(load, [filter]);

  async function handleApprove(id, approved) {
    try {
      await adminApi.approveComment(id, approved);
      setComments((prev) => (filter === 'all' ? prev.map((c) => (c.id === id ? { ...c, approved } : c)) : prev.filter((c) => c.id !== id)));
    } catch (err) {
      alert(err.message || 'Не удалось обновить');
    }
  }

  async function handleDelete(id) {
    if (!window.confirm('Удалить комментарий?')) return;
    try {
      await adminApi.deleteComment(id);
      setComments((prev) => prev.filter((c) => c.id !== id));
    } catch (err) {
      alert(err.message || 'Не удалось удалить');
    }
  }

  return (
    <div>
      <h1 className="admin-page-title">Комментарии</h1>

      <div className="admin-filters">
        <select value={filter} onChange={(e) => setFilter(e.target.value)}>
          <option value="pending">На модерации</option>
          <option value="approved">Опубликованные</option>
          <option value="all">Все</option>
        </select>
      </div>

      {error && <p className="admin-login__error">{error}</p>}
      {loading && <p className="admin-table__empty">Загрузка…</p>}
      {!loading && comments.length === 0 && <p className="admin-table__empty">Ничего нет</p>}

      <div className="booking-list">
        {comments.map((c) => (
          <div className={`booking-card booking-card--${c.approved ? 'paid' : 'pending'}`} key={c.id}>
            <div className="booking-card__head">
              <div>
                <p className="booking-card__customer">{c.user_name}</p>
                <span className="booking-card__phone">
                  {listingById.get(c.listing_id)?.name_ru || `#${c.listing_id}`}
                </span>
              </div>
              <div className="booking-card__meta">
                <span className="booking-card__date">{formatDate(c.created_at)}</span>
                <Stars value={c.rating} />
              </div>
            </div>

            <p className="booking-card__message">«{c.text}»</p>

            <div className="booking-card__footer">
              <span>{c.approved ? 'Опубликован' : 'Ожидает модерации'}</span>
              <div className="admin-table__actions">
                {!c.approved && (
                  <button className="admin-table__link" onClick={() => handleApprove(c.id, true)}>Одобрить</button>
                )}
                {c.approved && (
                  <button className="admin-table__link" onClick={() => handleApprove(c.id, false)}>Снять с публикации</button>
                )}
                <button className="admin-table__link admin-table__link--danger" onClick={() => handleDelete(c.id)}>Удалить</button>
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
