'use client';

import { useState } from 'react';
import { providerApi } from '@/lib/providerApi';
import { mediaUrl } from '@/lib/media';
import { T } from '@/context/AppProviders';

const EMPTY = {
  category_id: '',
  name_ru: '',
  name_kz: '',
  description_ru: '',
  description_kz: '',
  city: '',
  phone: '',
  price: 0,
  price_type: 'fixed',
  image_urls: [],
};

const PRICE_TYPES = [
  { value: 'fixed', ru: 'Фиксированная', kz: 'Тіркелген' },
  { value: 'from', ru: 'От (минимальная)', kz: 'Бастап' },
  { value: 'per_hour', ru: 'За час', kz: 'Сағатына' },
  { value: 'per_event', ru: 'За мероприятие', kz: 'Іс-шараға' },
  { value: 'negotiable', ru: 'Договорная', kz: 'Келісім бойынша' },
];

// Этап 11's "Добавить услугу" — deliberately compact (brief section 7:
// "не придумывай сложную тарифную систему", section 4's same instruction
// for the provider profile form applies here too): category, name, city,
// description, price + price type, photo. No rating/emoji/color/guest-
// range/video — those stay admin-only fields on ServiceForm.jsx, untouched.
//
// `restaurant` is the same form for a restaurant's general data: its category
// is fixed, it has its own phone, and its prices live in its menus.
// `provider`/`onEditContact` show a service's contact: the business's number.
export default function ProviderServiceForm({ categories, initial, listingId, onSaved, onCancel, restaurant = false, provider, onEditContact }) {
  const [values, setValues] = useState(() => ({
    ...EMPTY,
    ...initial,
    image_urls: initial?.image_urls || [],
  }));
  const [error, setError] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [uploading, setUploading] = useState(false);

  function set(key, value) {
    setValues((v) => ({ ...v, [key]: value }));
  }

  async function handleFiles(e) {
    const files = e.target.files;
    if (!files || files.length === 0) return;
    setError('');
    setUploading(true);
    try {
      const urls = await providerApi.uploadImages(files);
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

  async function handleSubmit(e) {
    e.preventDefault();
    if (uploading) {
      setError('Дождитесь окончания загрузки фото');
      return;
    }
    setError('');
    setSubmitting(true);
    try {
      const payload = {
        ...values,
        category_id: Number(values.category_id),
        price: Number(values.price) || 0,
        // Every card needs some fallback visual when there's no photo yet —
        // the compact form doesn't expose emoji/gradient pickers (admin's
        // ServiceForm still can, for anyone who wants to fine-tune it
        // later), so a fixed, on-brand default goes here instead.
        emoji: initial?.emoji || '✨',
        color_from: initial?.color_from || '#3a1420',
        color_to: initial?.color_to || '#d4af6a',
      };
      const saved = listingId
        ? await providerApi.updateListing(listingId, payload)
        : await providerApi.createListing(payload);
      onSaved(saved.listing);
    } catch (err) {
      setError(err.message || 'Не удалось сохранить услугу');
    } finally {
      setSubmitting(false);
    }
  }

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

      {!restaurant && (
      <label>
        <span>Категория</span>
        <select value={values.category_id} onChange={(e) => set('category_id', e.target.value)} required>
          <option value="" disabled>Выберите категорию</option>
          {categories.map((c) => (
            <option key={c.id} value={c.id}>{c.name_ru}</option>
          ))}
        </select>
      </label>
      )}

      <label>
        <span>Описание (рус)</span>
        <textarea rows="3" value={values.description_ru} onChange={(e) => set('description_ru', e.target.value)} />
      </label>
      <label>
        <span>Описание (қаз)</span>
        <textarea rows="3" value={values.description_kz} onChange={(e) => set('description_kz', e.target.value)} />
      </label>

      <label>
        <span>Город</span>
        <input value={values.city} onChange={(e) => set('city', e.target.value)} />
      </label>

      {restaurant ? (
        <label>
          <span><T ru="Телефон ресторана" kz="Мейрамхана телефоны" en="Restaurant phone" /></span>
          <input type="tel" maxLength={30} value={values.phone} onChange={(e) => set('phone', e.target.value)} placeholder="+7 700 000 00 00" />
          <small><T ru="Необязательно. Номер будет виден клиентам" kz="Міндетті емес. Нөмірді клиенттер көреді" en="Optional. Clients will see this number" /></small>
        </label>
      ) : (
        <>
          <label>
            <span>Цена, ₸</span>
            <input type="number" min="0" value={values.price} onChange={(e) => set('price', e.target.value)} />
          </label>
          <label>
            <span>Тип цены</span>
            <select value={values.price_type} onChange={(e) => set('price_type', e.target.value)}>
              {PRICE_TYPES.map((p) => (
                <option key={p.value} value={p.value}>{p.ru}</option>
              ))}
            </select>
          </label>
          <BusinessContact provider={provider} onEdit={onEditContact} />
        </>
      )}

      <label>
        <span>Фото</span>
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
      {uploading && (
        <p className="admin-upload-status">
          <span className="admin-spinner" aria-hidden="true" />
          Загружаем фото…
        </p>
      )}

      {error && <p className="admin-login__error">{error}</p>}

      <div style={{ display: 'flex', gap: 14 }}>
        <button type="submit" className="btn btn--gold" disabled={submitting || uploading}>
          {submitting ? 'Сохраняем…' : listingId ? 'Сохранить изменения' : 'Создать услугу'}
        </button>
        <button type="button" className="btn btn--outline" onClick={onCancel}>
          Отмена
        </button>
      </div>
    </form>
  );
}

// The business's number as clients get it. It belongs to the business, not to
// this service, so changing it goes to the profile form.
function BusinessContact({ provider, onEdit }) {
  if (!provider) return null;
  const phone = (provider.phone || '').trim();
  // The contact button clients get prefers these over the phone number.
  const messenger = provider.whatsapp?.trim() ? 'WhatsApp' : provider.telegram?.trim() ? 'Telegram' : null;
  return (
    <div className="provider-contact" data-testid="business-contact">
      <span><T ru="Контактный телефон бизнеса" kz="Бизнестің байланыс телефоны" en="Business contact phone" /></span>
      <strong>{phone || <T ru="Не указан" kz="Көрсетілмеген" en="Not set" />}</strong>
      <small>
        {phone
          ? <T ru="Этот номер увидят клиенты" kz="Бұл нөмірді клиенттер көреді" en="Clients will see this number" />
          : <T ru="Клиенты смогут связаться с вами только через чат или указанные мессенджеры" kz="Клиенттер сізбен тек чат немесе көрсетілген мессенджерлер арқылы байланыса алады" en="Clients can reach you only through chat or the messengers you added" />}
      </small>
      {phone && messenger && (
        <small><T ru={`Кнопка связи сейчас открывает ${messenger}`} kz={`Байланыс түймесі қазір ${messenger} ашады`} en={`The contact button currently opens ${messenger}`} /></small>
      )}
      <button type="button" className="admin-table__link" onClick={onEdit}>
        {phone ? <T ru="Изменить" kz="Өзгерту" en="Edit" /> : <T ru="Добавить" kz="Қосу" en="Add" />}
      </button>
    </div>
  );
}

// listingToPayload — reshapes a listing row (as returned by /me/listings or
// the catalog) back into the flat input shape this form and
// providerApi.updateListing expect, e.g. when reopening it for editing or
// re-sending every field alongside a plain is_active toggle (the backend's
// PUT is a full replace, not a patch — see listing_handler.go's Update), so
// every stored field has to be here or saving would wipe it.
export function listingToPayload(l) {
  return {
    category_id: l.category_id,
    name_ru: l.name_ru,
    name_kz: l.name_kz,
    description_ru: l.description_ru,
    description_kz: l.description_kz,
    city: l.city,
    phone: l.phone || '',
    price: l.price,
    price_type: l.price_type,
    min_guests: l.min_guests,
    max_guests: l.max_guests,
    image_urls: l.image_urls || [],
    video_urls: l.video_urls || [],
    emoji: l.emoji,
    color_from: l.color_from,
    color_to: l.color_to,
    address: l.address,
    latitude: l.latitude,
    longitude: l.longitude,
    place_id: l.place_id,
    capacity: l.capacity,
  };
}
