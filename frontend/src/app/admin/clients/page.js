'use client';

import { useEffect, useState } from 'react';
import { adminApi } from '@/lib/adminApi';
import { mediaUrl } from '@/lib/media';

const EVENT_TYPES = [
  { value: 'wedding', label: 'Свадьба' },
  { value: 'anniversary', label: 'Юбилей' },
  { value: 'corporate', label: 'Корпоратив' },
];

const EMPTY = { name: '', event_type: 'wedding', quote: '', photo_url: '' };

export default function AdminClientsPage() {
  const [clients, setClients] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [values, setValues] = useState(EMPTY);
  const [uploading, setUploading] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  function load() {
    setLoading(true);
    adminApi.clients()
      .then((d) => setClients(d.clients || []))
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }

  useEffect(load, []);

  function set(key, value) {
    setValues((v) => ({ ...v, [key]: value }));
  }

  async function handlePhotoFile(e) {
    const file = e.target.files?.[0];
    if (!file) return;
    setError('');
    setUploading(true);
    try {
      const urls = await adminApi.uploadImages([file]);
      set('photo_url', urls[0]);
    } catch (err) {
      setError(err.message || 'Не удалось загрузить фото');
    } finally {
      setUploading(false);
      e.target.value = '';
    }
  }

  async function handleSubmit(e) {
    e.preventDefault();
    if (uploading) return;
    setError('');
    setSubmitting(true);
    try {
      await adminApi.createClient(values);
      setValues(EMPTY);
      load();
    } catch (err) {
      setError(err.message || 'Не удалось сохранить');
    } finally {
      setSubmitting(false);
    }
  }

  async function handleDelete(id, name) {
    if (!window.confirm(`Удалить клиента «${name}»?`)) return;
    try {
      await adminApi.deleteClient(id);
      setClients((prev) => prev.filter((c) => c.id !== id));
    } catch (err) {
      alert(err.message || 'Не удалось удалить');
    }
  }

  return (
    <div>
      <h1 className="admin-page-title">Клиенты</h1>

      <form className="contacts__form admin-form" onSubmit={handleSubmit} style={{ maxWidth: 480, marginBottom: 40 }}>
        <label>
          <span>Имя клиента</span>
          <input value={values.name} onChange={(e) => set('name', e.target.value)} required />
        </label>
        <label>
          <span>Тип торжества</span>
          <select value={values.event_type} onChange={(e) => set('event_type', e.target.value)} required>
            {EVENT_TYPES.map((t) => (
              <option key={t.value} value={t.value}>{t.label}</option>
            ))}
          </select>
        </label>
        <label>
          <span>Короткий отзыв (необязательно)</span>
          <textarea rows="3" value={values.quote} onChange={(e) => set('quote', e.target.value)} />
        </label>
        <label>
          <span>Фото</span>
          <input type="file" accept="image/png,image/jpeg,image/webp,image/gif" onChange={handlePhotoFile} disabled={uploading} />
        </label>
        {values.photo_url && (
          <img src={mediaUrl(values.photo_url)} alt="" style={{ width: 90, height: 90, objectFit: 'cover', borderRadius: 12 }} />
        )}
        {uploading && <p className="admin-upload-status"><span className="admin-spinner" aria-hidden="true" />Загружаем фото…</p>}

        {error && <p className="admin-login__error">{error}</p>}

        <button type="submit" className="btn btn--gold" disabled={submitting || uploading}>
          {submitting ? 'Сохраняем…' : 'Добавить клиента'}
        </button>
      </form>

      {loading && <p className="admin-table__empty">Загрузка…</p>}
      {!loading && clients.length === 0 && <p className="admin-table__empty">Клиентов пока нет</p>}

      <div className="admin-image-grid">
        {clients.map((cl) => (
          <div className="admin-image-thumb" key={cl.id} style={{ width: 140, height: 140 }}>
            {cl.photo_url
              ? <img src={mediaUrl(cl.photo_url)} alt="" />
              : <div style={{ width: '100%', height: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'var(--surface-tint)' }}>{cl.name?.[0]}</div>}
            <span className="admin-image-thumb__badge">{cl.name}</span>
            <button type="button" className="admin-image-thumb__remove" onClick={() => handleDelete(cl.id, cl.name)} aria-label="Удалить">✕</button>
          </div>
        ))}
      </div>
    </div>
  );
}
