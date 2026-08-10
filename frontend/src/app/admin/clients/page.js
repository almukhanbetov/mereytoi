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

  async function handleDelete(id, name) {
    if (!window.confirm(`Удалить клиента «${name}»? Это действие нельзя отменить.`)) return;
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
        <h1 className="admin-page-title">Клиенты</h1>
        <Link href="/admin/clients/new" className="btn btn--gold btn--sm">+ Добавить</Link>
      </div>

      {error && <p className="admin-login__error">{error}</p>}

      <div className="admin-table-wrap">
        <table className="admin-table">
          <thead>
            <tr>
              <th>Клиент</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {loading && (
              <tr><td colSpan={2} className="admin-table__empty">Загрузка…</td></tr>
            )}
            {!loading && clients.length === 0 && (
              <tr><td colSpan={2} className="admin-table__empty">Клиентов пока нет</td></tr>
            )}
            {clients.map((cl) => (
              <tr key={cl.id}>
                <td className="admin-table__name-cell">
                  {cl.photo_url
                    ? <img src={mediaUrl(cl.photo_url)} alt="" className="admin-table__thumb" />
                    : <span>{cl.name?.[0]?.toUpperCase()}</span>}
                  {cl.name}
                </td>
                <td className="admin-table__actions">
                  <Link href={`/admin/clients/edit/${cl.id}`} className="admin-icon-btn" aria-label="Редактировать" title="Редактировать">
                    ✎
                  </Link>
                  <button
                    type="button"
                    className="admin-icon-btn admin-icon-btn--danger"
                    onClick={() => handleDelete(cl.id, cl.name)}
                    aria-label="Удалить"
                    title="Удалить"
                  >
                    🗑
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
