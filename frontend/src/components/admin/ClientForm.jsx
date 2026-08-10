'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { adminApi } from '@/lib/adminApi';
import { mediaUrl } from '@/lib/media';

export default function ClientForm({ initial, clientId }) {
  const router = useRouter();
  const [photoUrl, setPhotoUrl] = useState(initial?.photo_url || '');
  const [error, setError] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [uploading, setUploading] = useState(false);

  async function handlePhotoFile(e) {
    const file = e.target.files?.[0];
    if (!file) return;
    setError('');
    setUploading(true);
    try {
      const urls = await adminApi.uploadImages([file]);
      setPhotoUrl(urls[0]);
    } catch (err) {
      setError(err.message || 'Не удалось загрузить логотип');
    } finally {
      setUploading(false);
      e.target.value = '';
    }
  }

  async function handleSubmit(e) {
    e.preventDefault();
    if (uploading) {
      setError('Дождитесь окончания загрузки перед сохранением');
      return;
    }
    if (!photoUrl) {
      setError('Загрузите изображение логотипа');
      return;
    }
    setError('');
    setSubmitting(true);
    try {
      const payload = { photo_url: photoUrl };
      if (clientId) await adminApi.updateClient(clientId, payload);
      else await adminApi.createClient(payload);
      router.push('/admin/clients');
    } catch (err) {
      setError(err.message || 'Не удалось сохранить логотип');
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <form className="contacts__form admin-form" onSubmit={handleSubmit} style={{ maxWidth: 480 }}>
      <label>
        <span>Логотип</span>
        <input type="file" accept="image/png,image/jpeg,image/webp,image/gif" onChange={handlePhotoFile} disabled={uploading} />
      </label>

      {photoUrl && (
        <div style={{ width: 160, height: 160, borderRadius: 12, background: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 16 }}>
          <img src={mediaUrl(photoUrl)} alt="" style={{ maxWidth: '100%', maxHeight: '100%', objectFit: 'contain' }} />
        </div>
      )}
      {uploading && (
        <p className="admin-upload-status">
          <span className="admin-spinner" aria-hidden="true" />
          Загружаем логотип…
        </p>
      )}

      {error && <p className="admin-login__error">{error}</p>}

      <div style={{ display: 'flex', gap: 14 }}>
        <button type="submit" className="btn btn--gold" disabled={submitting || uploading}>
          {submitting ? 'Сохраняем…' : clientId ? 'Сохранить изменения' : 'Добавить логотип'}
        </button>
        <button type="button" className="btn btn--outline" onClick={() => router.back()}>
          Отмена
        </button>
      </div>
    </form>
  );
}
