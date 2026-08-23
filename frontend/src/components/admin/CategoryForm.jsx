'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { adminApi } from '@/lib/adminApi';
import { mediaUrl } from '@/lib/media';

export default function CategoryForm({ initial, categoryId }) {
  const router = useRouter();
  const [slug, setSlug] = useState(initial?.slug || '');
  const [nameRu, setNameRu] = useState(initial?.name_ru || '');
  const [nameKz, setNameKz] = useState(initial?.name_kz || '');
  const [position, setPosition] = useState(initial?.position ?? 0);
  const [imageUrl, setImageUrl] = useState(initial?.image_url || '');
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
      setImageUrl(urls[0]);
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
      const payload = {
        slug: slug.trim(),
        name_ru: nameRu.trim(),
        name_kz: nameKz.trim(),
        position: Number(position) || 0,
        image_url: imageUrl,
      };
      if (categoryId) await adminApi.updateCategory(categoryId, payload);
      else await adminApi.createCategory(payload);
      router.push('/admin');
    } catch (err) {
      setError(err.message || 'Не удалось сохранить категорию');
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <form className="contacts__form admin-form" onSubmit={handleSubmit} style={{ maxWidth: 480 }}>
      <label>
        <span>Slug (латиницей, для ссылок)</span>
        <input
          type="text"
          value={slug}
          onChange={(e) => setSlug(e.target.value)}
          placeholder="hosts"
          required
        />
      </label>
      <label>
        <span>Название (рус)</span>
        <input type="text" value={nameRu} onChange={(e) => setNameRu(e.target.value)} required />
      </label>
      <label>
        <span>Название (қаз)</span>
        <input type="text" value={nameKz} onChange={(e) => setNameKz(e.target.value)} required />
      </label>
      <label>
        <span>Позиция в списке</span>
        <input type="number" value={position} onChange={(e) => setPosition(e.target.value)} />
      </label>

      <label>
        <span>Фото категории</span>
        <input type="file" accept="image/png,image/jpeg,image/webp,image/gif" onChange={handlePhotoFile} disabled={uploading} />
      </label>

      <div
        style={{
          width: '100%', maxWidth: 320, aspectRatio: '16 / 10', borderRadius: 12,
          background: 'var(--surface-tint)', border: '1px solid var(--border)',
          display: 'flex', alignItems: 'center', justifyContent: 'center', overflow: 'hidden',
        }}
      >
        {imageUrl ? (
          <img src={mediaUrl(imageUrl)} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
        ) : (
          <span style={{ color: 'var(--text-muted)', fontSize: 13 }}>Фото не загружено</span>
        )}
      </div>

      {imageUrl && (
        <button type="button" className="admin-table__link admin-table__link--danger" style={{ alignSelf: 'flex-start' }} onClick={() => setImageUrl('')}>
          Удалить фото
        </button>
      )}

      {uploading && (
        <p className="admin-upload-status">
          <span className="admin-spinner" aria-hidden="true" />
          Загружаем фото…
        </p>
      )}

      {error && <p className="admin-login__error">{error}</p>}

      <div style={{ display: 'flex', gap: 14 }}>
        <button type="submit" className="btn btn--gold" disabled={submitting}>
          {submitting ? 'Сохраняем…' : categoryId ? 'Сохранить изменения' : 'Добавить категорию'}
        </button>
        <button type="button" className="btn btn--outline" onClick={() => router.back()}>
          Отмена
        </button>
      </div>
    </form>
  );
}
