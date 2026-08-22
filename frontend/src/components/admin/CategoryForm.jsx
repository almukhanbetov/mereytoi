'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { adminApi } from '@/lib/adminApi';

export default function CategoryForm({ initial, categoryId }) {
  const router = useRouter();
  const [slug, setSlug] = useState(initial?.slug || '');
  const [nameRu, setNameRu] = useState(initial?.name_ru || '');
  const [nameKz, setNameKz] = useState(initial?.name_kz || '');
  const [position, setPosition] = useState(initial?.position ?? 0);
  const [error, setError] = useState('');
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit(e) {
    e.preventDefault();
    setError('');
    setSubmitting(true);
    try {
      const payload = {
        slug: slug.trim(),
        name_ru: nameRu.trim(),
        name_kz: nameKz.trim(),
        position: Number(position) || 0,
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
