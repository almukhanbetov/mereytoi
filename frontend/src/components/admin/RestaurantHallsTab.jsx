'use client';

import { useState } from 'react';
import { adminApi } from '@/lib/adminApi';
import { formatPrice } from '@/lib/format';
import { mediaUrl } from '@/lib/media';

const EMPTY = { name_ru: '', name_kz: '', description_ru: '', description_kz: '', capacity: 0, price: 0, image_urls: [], is_active: true, sort_order: 0 };

function sortByOrder(list) {
  return [...list].sort((a, b) => a.sort_order - b.sort_order);
}

/** Brief section 2 — hall CRUD. A single open-at-a-time inline form (no
 * modal/route) replaces either the "+ Добавить зал" card or one existing
 * card in place — "не делать огромные формы", per the brief's own UX
 * section. Reordering is two small ↑/↓ buttons that swap sort_order with
 * the neighboring card rather than drag-and-drop — a deliberately more
 * reliable, keyboard-accessible equivalent given this environment has no
 * way to visually verify a drag interaction actually works.
 *
 * `halls`/`refresh` come from the parent tab shell (RestaurantAdminTabs),
 * not owned locally — the Menus tab's own hall-picker dropdown needs the
 * exact same up-to-date list, so both tabs share one source of truth
 * instead of each keeping an independent copy that could drift apart. */
export default function RestaurantHallsTab({ listingId, halls, refresh }) {
  const sorted = sortByOrder(halls);
  const [editingId, setEditingId] = useState(null); // null | 'new' | hall id
  const [form, setForm] = useState(EMPTY);
  const [saving, setSaving] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState('');

  function startCreate() {
    setForm({ ...EMPTY, sort_order: sorted.length });
    setEditingId('new');
    setError('');
  }
  function startEdit(hall) {
    setForm({ ...hall });
    setEditingId(hall.id);
    setError('');
  }
  function cancel() {
    setEditingId(null);
    setError('');
  }

  async function handleFiles(e) {
    const files = e.target.files;
    if (!files?.length) return;
    setUploading(true);
    setError('');
    try {
      const urls = await adminApi.uploadImages(files);
      setForm((f) => ({ ...f, image_urls: [...(f.image_urls || []), ...urls] }));
    } catch (err) {
      setError(err.message || 'Не удалось загрузить фото');
    } finally {
      setUploading(false);
      e.target.value = '';
    }
  }
  function removeImage(url) {
    setForm((f) => ({ ...f, image_urls: f.image_urls.filter((u) => u !== url) }));
  }

  async function save() {
    setSaving(true);
    setError('');
    try {
      const payload = {
        ...form,
        capacity: Number(form.capacity) || 0,
        price: Number(form.price) || 0,
        sort_order: Number(form.sort_order) || 0,
      };
      if (editingId === 'new') {
        await adminApi.createHall(listingId, payload);
      } else {
        await adminApi.updateHall(listingId, editingId, payload);
      }
      await refresh();
      setEditingId(null);
    } catch (err) {
      setError(err.message || 'Не удалось сохранить зал');
    } finally {
      setSaving(false);
    }
  }

  async function toggleActive(hall) {
    try {
      await adminApi.updateHall(listingId, hall.id, { ...hall, is_active: !hall.is_active });
      await refresh();
    } catch (err) {
      alert(err.message || 'Не удалось изменить статус зала');
    }
  }

  async function remove(hall) {
    if (!window.confirm(`Удалить зал «${hall.name_ru}»? Прошлые заявки, где он уже выбран, сохранят его название.`)) return;
    try {
      await adminApi.deleteHall(listingId, hall.id);
      await refresh();
    } catch (err) {
      alert(err.message || 'Не удалось удалить зал');
    }
  }

  async function move(hall, direction) {
    const idx = sorted.findIndex((h) => h.id === hall.id);
    const swapIdx = idx + direction;
    if (swapIdx < 0 || swapIdx >= sorted.length) return;
    const a = sorted[idx];
    const b = sorted[swapIdx];
    try {
      await Promise.all([
        adminApi.updateHall(listingId, a.id, { ...a, sort_order: b.sort_order }),
        adminApi.updateHall(listingId, b.id, { ...b, sort_order: a.sort_order }),
      ]);
      await refresh();
    } catch (err) {
      alert(err.message || 'Не удалось изменить порядок');
    }
  }

  return (
    <div>
      <div className="admin-page-head" style={{ marginBottom: 18 }}>
        <h2 className="admin-section-title" style={{ margin: 0 }}>Залы</h2>
        {editingId === null && (
          <button type="button" className="btn btn--gold btn--sm" onClick={startCreate}>+ Добавить зал</button>
        )}
      </div>

      {sorted.length === 0 && editingId !== 'new' && (
        <p className="admin-table__empty">Залы ещё не добавлены</p>
      )}

      <div className="admin-card-grid">
        {editingId === 'new' && (
          <HallForm form={form} setForm={setForm} onSave={save} onCancel={cancel} saving={saving} error={error} uploading={uploading} onFiles={handleFiles} onRemoveImage={removeImage} />
        )}
        {sorted.map((hall, i) =>
          editingId === hall.id ? (
            <HallForm key={hall.id} form={form} setForm={setForm} onSave={save} onCancel={cancel} saving={saving} error={error} uploading={uploading} onFiles={handleFiles} onRemoveImage={removeImage} />
          ) : (
            <div className={`admin-card${hall.is_active ? '' : ' admin-card--inactive'}`} key={hall.id}>
              <div className="admin-card__head">
                <h3 className="admin-card__title">{hall.name_ru}</h3>
                <span className={`admin-card__badge${hall.is_active ? '' : ' admin-card__badge--off'}`}>
                  {hall.is_active ? 'Активен' : 'Выключен'}
                </span>
              </div>
              {hall.image_urls?.[0] && (
                <img src={mediaUrl(hall.image_urls[0])} alt="" style={{ width: '100%', borderRadius: 10, aspectRatio: '16/9', objectFit: 'cover' }} />
              )}
              <div className="admin-card__meta">
                <span>Вместимость: {hall.capacity || '—'}</span>
                <span>Цена: {hall.price > 0 ? formatPrice(hall.price) : 'как у ресторана'}</span>
              </div>
              <div className="admin-card__actions">
                <button type="button" className="admin-table__link" onClick={() => startEdit(hall)}>Изменить</button>
                <button type="button" className="admin-table__link" onClick={() => toggleActive(hall)}>
                  {hall.is_active ? 'Деактивировать' : 'Активировать'}
                </button>
                <button type="button" className="admin-table__link admin-table__link--danger" onClick={() => remove(hall)}>Удалить</button>
                <span className="admin-card__order">
                  <button type="button" className="admin-icon-btn" disabled={i === 0} onClick={() => move(hall, -1)} aria-label="Выше">↑</button>
                  <button type="button" className="admin-icon-btn" disabled={i === sorted.length - 1} onClick={() => move(hall, 1)} aria-label="Ниже">↓</button>
                </span>
              </div>
            </div>
          )
        )}
      </div>
    </div>
  );
}

function HallForm({ form, setForm, onSave, onCancel, saving, error, uploading, onFiles, onRemoveImage }) {
  function set(key, value) {
    setForm((f) => ({ ...f, [key]: value }));
  }

  return (
    <div className="admin-card admin-card--form">
      <div className="form-row">
        <label>
          <span>Название (рус)</span>
          <input value={form.name_ru} onChange={(e) => set('name_ru', e.target.value)} required />
        </label>
        <label>
          <span>Название (қаз)</span>
          <input value={form.name_kz} onChange={(e) => set('name_kz', e.target.value)} required />
        </label>
      </div>
      <div className="form-row">
        <label>
          <span>Описание (рус)</span>
          <textarea rows="2" value={form.description_ru} onChange={(e) => set('description_ru', e.target.value)} />
        </label>
        <label>
          <span>Описание (қаз)</span>
          <textarea rows="2" value={form.description_kz} onChange={(e) => set('description_kz', e.target.value)} />
        </label>
      </div>
      <div className="form-row">
        <label>
          <span>Вместимость (гостей)</span>
          <input type="number" min="0" value={form.capacity} onChange={(e) => set('capacity', e.target.value)} />
        </label>
        <label>
          <span>Цена, ₸ (0 — как у ресторана)</span>
          <input type="number" min="0" value={form.price} onChange={(e) => set('price', e.target.value)} />
        </label>
      </div>
      <div className="form-row">
        <label>
          <span>Порядок сортировки</span>
          <input type="number" value={form.sort_order} onChange={(e) => set('sort_order', e.target.value)} />
        </label>
        <label style={{ flexDirection: 'row', alignItems: 'center', gap: 8, justifyContent: 'flex-start', paddingTop: 22 }}>
          <input type="checkbox" checked={form.is_active} onChange={(e) => set('is_active', e.target.checked)} style={{ width: 'auto' }} />
          <span style={{ fontWeight: 400, color: 'var(--text)' }}>Активен</span>
        </label>
      </div>

      <label>
        <span>Фото зала</span>
        <input type="file" accept="image/png,image/jpeg,image/webp,image/gif" multiple onChange={onFiles} disabled={uploading} />
      </label>
      {form.image_urls?.length > 0 && (
        <div className="admin-image-grid">
          {form.image_urls.map((url) => (
            <div className="admin-image-thumb" key={url}>
              <img src={mediaUrl(url)} alt="" />
              <button type="button" className="admin-image-thumb__remove" onClick={() => onRemoveImage(url)} aria-label="Удалить фото">✕</button>
            </div>
          ))}
        </div>
      )}

      {error && <p className="admin-login__error">{error}</p>}

      <div style={{ display: 'flex', gap: 12 }}>
        <button type="button" className="btn btn--gold btn--sm" onClick={onSave} disabled={saving || uploading}>
          {saving ? 'Сохраняем…' : 'Сохранить зал'}
        </button>
        <button type="button" className="btn btn--outline btn--sm" onClick={onCancel}>Отмена</button>
      </div>
    </div>
  );
}
