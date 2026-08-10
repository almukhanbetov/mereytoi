'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { adminApi } from '@/lib/adminApi';
import { mediaUrl } from '@/lib/media';

const EMPTY = { name: '', photo_url: '' };

export default function ClientForm({ initial, clientId }) {
  const router = useRouter();
  const [values, setValues] = useState(() => ({ ...EMPTY, ...initial }));
  const [error, setError] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [uploading, setUploading] = useState(false);

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
    if (uploading) {
      setError('Дождитесь окончания загрузки фото перед сохранением');
      return;
    }
    setError('');
    setSubmitting(true);
    try {
      if (clientId) await adminApi.updateClient(clientId, values);
      else await adminApi.createClient(values);
      router.push('/admin/clients');
    } catch (err) {
      setError(err.message || 'Не удалось сохранить клиента');
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <form className="contacts__form admin-form" onSubmit={handleSubmit} style={{ maxWidth: 480 }}>
      <label>
        <span>Имя клиента</span>
        <input value={values.name} onChange={(e) => set('name', e.target.value)} required />
      </label>

      <label>
        <span>Фото</span>
        <input type="file" accept="image/png,image/jpeg,image/webp,image/gif" onChange={handlePhotoFile} disabled={uploading} />
      </label>

      {values.photo_url && (
        <img src={mediaUrl(values.photo_url)} alt="" style={{ width: 120, height: 120, objectFit: 'cover', borderRadius: 12 }} />
      )}
      {uploading && (
        <p className="admin-upload-status">
          <span className="admin-spinner" aria-hidden="true" />
          Загружаем фото…
        </p>
      )}

      {error && <p className="admin-login__error">{error}</p>}

      <div style={{ display: 'flex', gap: 14 }}>
        <button type="submit" className="btn btn--gold" disabled={submitting || uploading}>
          {submitting ? 'Сохраняем…' : clientId ? 'Сохранить изменения' : 'Добавить клиента'}
        </button>
        <button type="button" className="btn btn--outline" onClick={() => router.back()}>
          Отмена
        </button>
      </div>
    </form>
  );
}
