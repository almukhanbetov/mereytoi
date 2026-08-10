'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { adminApi } from '@/lib/adminApi';
import { mediaUrl } from '@/lib/media';

const EMPTY = {
  category_id: '',
  name_ru: '',
  name_kz: '',
  description_ru: '',
  description_kz: '',
  city: '',
  phone: '',
  price: 0,
  min_guests: 0,
  max_guests: 0,
  rating: 0,
  emoji: '✨',
  color_from: '#3a1420',
  color_to: '#d4af6a',
  image_urls: [],
  video_url: '',
};

export default function ServiceForm({ categories, initial, listingId }) {
  const router = useRouter();
  const [values, setValues] = useState(() => ({ ...EMPTY, ...initial, image_urls: initial?.image_urls || [] }));
  const [error, setError] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [uploadingVideo, setUploadingVideo] = useState(false);

  function set(key, value) {
    setValues((v) => ({ ...v, [key]: value }));
  }

  async function handleFiles(e) {
    const files = e.target.files;
    if (!files || files.length === 0) return;
    setError('');
    setUploading(true);
    try {
      const urls = await adminApi.uploadImages(files);
      setValues((v) => ({ ...v, image_urls: [...v.image_urls, ...urls] }));
    } catch (err) {
      setError(err.message || 'Не удалось загрузить фото');
    } finally {
      setUploading(false);
      e.target.value = '';
    }
  }

  function removeImage(url) {
    setValues((v) => ({ ...v, image_urls: v.image_urls.filter((u) => u !== url) }));
  }

  async function handleVideoFile(e) {
    const file = e.target.files?.[0];
    if (!file) return;
    setError('');
    setUploadingVideo(true);
    try {
      const url = await adminApi.uploadVideo(file);
      set('video_url', url);
    } catch (err) {
      setError(err.message || 'Не удалось загрузить видео');
    } finally {
      setUploadingVideo(false);
      e.target.value = '';
    }
  }

  function removeVideo() {
    set('video_url', '');
  }

  async function handleSubmit(e) {
    e.preventDefault();
    if (uploading || uploadingVideo) {
      setError('Дождитесь окончания загрузки файлов перед сохранением');
      return;
    }
    setError('');
    setSubmitting(true);
    try {
      const payload = {
        ...values,
        category_id: Number(values.category_id),
        price: Number(values.price) || 0,
        min_guests: Number(values.min_guests) || 0,
        max_guests: Number(values.max_guests) || 0,
        rating: Number(values.rating) || 0,
      };
      if (listingId) await adminApi.updateListing(listingId, payload);
      else await adminApi.createListing(payload);
      const category = categories.find((c) => c.id === payload.category_id);
      router.push(category ? `/admin/services/${category.slug}` : '/admin/services');
    } catch (err) {
      setError(err.message || 'Не удалось сохранить услугу');
    } finally {
      setSubmitting(false);
    }
  }

  const hasImages = values.image_urls.length > 0;

  return (
    <form className="contacts__form admin-form" onSubmit={handleSubmit}>
      <div className="form-row">
        <label>
          <span>Название (рус)</span>
          <input value={values.name_ru} onChange={(e) => set('name_ru', e.target.value)} required />
        </label>
        <label>
          <span>Название (қаз)</span>
          <input value={values.name_kz} onChange={(e) => set('name_kz', e.target.value)} required />
        </label>
      </div>

      <label>
        <span>Категория</span>
        <select value={values.category_id} onChange={(e) => set('category_id', e.target.value)} required>
          <option value="" disabled>Выберите категорию</option>
          {categories.map((c) => (
            <option key={c.id} value={c.id}>{c.name_ru}</option>
          ))}
        </select>
      </label>

      <div className="form-row">
        <label>
          <span>Описание (рус)</span>
          <textarea rows="3" value={values.description_ru} onChange={(e) => set('description_ru', e.target.value)} />
        </label>
        <label>
          <span>Описание (қаз)</span>
          <textarea rows="3" value={values.description_kz} onChange={(e) => set('description_kz', e.target.value)} />
        </label>
      </div>

      <div className="form-row">
        <label>
          <span>Город</span>
          <input value={values.city} onChange={(e) => set('city', e.target.value)} />
        </label>
        <label>
          <span>Телефон</span>
          <input value={values.phone} onChange={(e) => set('phone', e.target.value)} placeholder="+7 700 000 00 00" />
        </label>
      </div>

      <div className="form-row">
        <label>
          <span>Цена, ₸ (0 — по запросу)</span>
          <input type="number" min="0" value={values.price} onChange={(e) => set('price', e.target.value)} />
        </label>
        <label>
          <span>Рейтинг (0–5)</span>
          <input type="number" min="0" max="5" step="0.1" value={values.rating} onChange={(e) => set('rating', e.target.value)} />
        </label>
      </div>

      <div className="form-row">
        <label>
          <span>Мин. гостей (для ресторанов/локаций — цена за персону)</span>
          <input type="number" min="0" value={values.min_guests} onChange={(e) => set('min_guests', e.target.value)} placeholder="0 — не применимо" />
        </label>
        <label>
          <span>Макс. гостей</span>
          <input type="number" min="0" value={values.max_guests} onChange={(e) => set('max_guests', e.target.value)} placeholder="0 — не применимо" />
        </label>
      </div>

      <div className="form-row">
        <label>
          <span>Эмодзи-иконка (запасной вариант, если фото нет)</span>
          <input value={values.emoji} onChange={(e) => set('emoji', e.target.value)} maxLength={4} />
        </label>
        <label>
          <span>Градиент карточки (запасной вариант)</span>
          <div className="admin-color-row">
            <input type="color" value={values.color_from} onChange={(e) => set('color_from', e.target.value)} />
            <input type="color" value={values.color_to} onChange={(e) => set('color_to', e.target.value)} />
          </div>
        </label>
      </div>

      <label>
        <span>Фото (одно или несколько — первое станет фоном карточки)</span>
        <input type="file" accept="image/png,image/jpeg,image/webp,image/gif" multiple onChange={handleFiles} disabled={uploading} />
      </label>

      {values.image_urls.length > 0 && (
        <div className="admin-image-grid">
          {values.image_urls.map((url, i) => (
            <div className="admin-image-thumb" key={url}>
              <img src={mediaUrl(url)} alt="" />
              {i === 0 && <span className="admin-image-thumb__badge">Обложка</span>}
              <button type="button" className="admin-image-thumb__remove" onClick={() => removeImage(url)} aria-label="Удалить фото">✕</button>
            </div>
          ))}
        </div>
      )}
      {uploading && <p className="admin-login__title" style={{ margin: 0 }}>Загружаем фото…</p>}

      <label>
        <span>Видео (mp4, webm, mov — до 100MB)</span>
        <input type="file" accept="video/mp4,video/webm,video/quicktime" onChange={handleVideoFile} disabled={uploadingVideo} />
      </label>

      {values.video_url && (
        <div className="admin-video-preview">
          <video src={mediaUrl(values.video_url)} controls />
          <div className="admin-video-preview__actions">
            <a className="admin-table__link" href={mediaUrl(values.video_url)} download target="_blank" rel="noopener noreferrer">
              Скачать видео
            </a>
            <button type="button" className="admin-table__link admin-table__link--danger" onClick={removeVideo}>
              Удалить видео
            </button>
          </div>
        </div>
      )}
      {uploadingVideo && <p className="admin-login__title" style={{ margin: 0 }}>Загружаем видео…</p>}

      <div
        className="admin-preview"
        style={
          hasImages
            ? { backgroundImage: `url(${mediaUrl(values.image_urls[0])})`, backgroundSize: 'cover', backgroundPosition: 'center' }
            : { background: `linear-gradient(150deg, ${values.color_from}, ${values.color_to})` }
        }
      >
        {!hasImages && values.emoji}
      </div>

      {error && <p className="admin-login__error">{error}</p>}

      <div style={{ display: 'flex', gap: 14 }}>
        <button type="submit" className="btn btn--gold" disabled={submitting || uploading || uploadingVideo}>
          {submitting ? 'Сохраняем…' : listingId ? 'Сохранить изменения' : 'Создать услугу'}
        </button>
        <button type="button" className="btn btn--outline" onClick={() => router.back()}>
          Отмена
        </button>
      </div>
    </form>
  );
}
