'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { adminApi } from '@/lib/adminApi';
import { mediaUrl } from '@/lib/media';

export default function AdminClientsPage() {
  const [clients, setClients] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  function load() {
    setLoading(true);
    adminApi.clients()
      .then((d) => setClients(d.clients || []))
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }

  useEffect(load, []);

  async function handleDelete(id) {
    if (!window.confirm('Удалить этот логотип? Это действие нельзя отменить.')) return;
    try {
      await adminApi.deleteClient(id);
      setClients((prev) => prev.filter((c) => c.id !== id));
    } catch (err) {
      alert(err.message || 'Не удалось удалить');
    }
  }

  return (
    <div>
      <div className="admin-page-head">
        <h1 className="admin-page-title">Клиенты (логотипы)</h1>
        <Link href="/admin/clients/new" className="btn btn--gold btn--sm">+ Добавить</Link>
      </div>

      {error && <p className="admin-login__error">{error}</p>}
      {loading && <p className="admin-table__empty">Загрузка…</p>}
      {!loading && clients.length === 0 && <p className="admin-table__empty">Логотипов пока нет</p>}

      <div className="admin-logo-grid">
        {clients.map((cl) => (
          <div className="admin-logo-card" key={cl.id}>
            <div className="admin-logo-card__photo">
              <img src={mediaUrl(cl.photo_url)} alt="" />
            </div>
            <div className="admin-logo-card__actions">
              <Link href={`/admin/clients/edit/${cl.id}`} className="admin-icon-btn" aria-label="Редактировать" title="Редактировать">
                ✎
              </Link>
              <button
                type="button"
                className="admin-icon-btn admin-icon-btn--danger"
                onClick={() => handleDelete(cl.id)}
                aria-label="Удалить"
                title="Удалить"
              >
                🗑
              </button>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
