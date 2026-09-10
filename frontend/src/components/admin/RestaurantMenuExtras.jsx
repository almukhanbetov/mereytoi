'use client';

import { useState } from 'react';
import { adminApi } from '@/lib/adminApi';
import { formatPrice } from '@/lib/format';

const EMPTY = { type: 'other', title_ru: '', title_kz: '', price: '', unit: '', description_ru: '', description_kz: '', sort_order: 0 };

// Suggested presets only — Type stays a free-form string on the backend
// (same as Event.Type / Booking.Status), never a fixed enum.
const EXTRA_PRESETS = [
  { type: 'kids_table', label: 'Детский стол' },
  { type: 'artists_table', label: 'Стол артистов' },
  { type: 'service_fee', label: 'Сервисный сбор' },
  { type: 'rental', label: 'Аренда' },
  { type: 'corkage', label: 'Пробковый сбор' },
  { type: 'decor', label: 'Декор' },
  { type: 'other', label: 'Другое условие' },
];
const TYPE_LABELS = Object.fromEntries(EXTRA_PRESETS.map((p) => [p.type, p.label]));

// unit is the free-form price mode already understood by the public menu
// calculator (RestaurantMenuCalculator): 'percent' / 'per_guest' are
// special-cased there, everything else is a flat amount. No new types.
const UNIT_OPTIONS = [
  { value: '', label: 'Фиксированная сумма' },
  { value: 'per_guest', label: 'На каждого гостя' },
  { value: 'per_item', label: 'За единицу' },
  { value: 'percent', label: 'Процент от суммы заказа' },
];

function typeLabel(type) {
  return TYPE_LABELS[type] || type || 'Опция';
}

function priceLabel(extra) {
  const u = (extra.unit || '').trim().toLowerCase();
  if (u === 'percent') return `${extra.price}%`;
  if (u === 'per_guest') return `${formatPrice(extra.price)} / гость`;
  if (u === 'per_item') return `${formatPrice(extra.price)} / шт.`;
  return formatPrice(extra.price);
}

/** Extras CRUD for one menu. Frontend-only restyle — the ListingMenuExtra
 * API and model (type / title / price uint / unit string / description /
 * sort_order) are untouched. */
export default function RestaurantMenuExtras({ listingId, menu, refresh }) {
  const extras = [...(menu.extras || [])].sort((a, b) => a.sort_order - b.sort_order);
  const [form, setForm] = useState(null); // null | 'new' | extra.id being edited
  const [values, setValues] = useState(EMPTY);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [confirmId, setConfirmId] = useState(null);

  function startCreate(preset) {
    setValues({
      ...EMPTY,
      type: preset?.type || 'other',
      title_ru: preset?.label || '',
      title_kz: preset?.label || '',
      sort_order: extras.length,
    });
    setForm('new');
    setError('');
  }
  function startEdit(extra) {
    setValues({
      type: extra.type || 'other',
      title_ru: extra.title_ru || '',
      title_kz: extra.title_kz || '',
      price: extra.price ? String(extra.price) : '',
      unit: extra.unit || '',
      description_ru: extra.description_ru || '',
      description_kz: extra.description_kz || '',
      sort_order: extra.sort_order ?? 0,
    });
    setForm(extra.id);
    setError('');
  }

  async function save() {
    if (!values.title_ru.trim() || !values.title_kz.trim()) {
      setError('Укажите название на русском и казахском');
      return;
    }
    setBusy(true);
    setError('');
    try {
      const payload = { ...values, price: Number(values.price) || 0 };
      if (form === 'new') await adminApi.createExtra(listingId, menu.id, payload);
      else await adminApi.updateExtra(listingId, menu.id, form, payload);
      await refresh();
      setForm(null);
    } catch (err) {
      setError(err.message || 'Не удалось сохранить условие');
    } finally {
      setBusy(false);
    }
  }

  async function remove(extra) {
    setBusy(true);
    setError('');
    try {
      await adminApi.deleteExtra(listingId, menu.id, extra.id);
      await refresh();
      setConfirmId(null);
    } catch (err) {
      setError(err.message || 'Не удалось удалить условие');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div>
      <div className="menu-builder__block-head">
        <span className="menu-builder__block-title">Дополнительные опции</span>
      </div>

      {error && <p className="admin-banner admin-banner--error">{error}</p>}

      {extras.length === 0 && form === null && (
        <p className="admin-empty__text" style={{ textAlign: 'left', margin: '4px 0' }}>
          Дополнительных опций нет — например, алкоголь, детский стол, сервисный сбор или декор.
        </p>
      )}

      <div className="menu-item-list">
        {extras.map((extra) =>
          form === extra.id ? (
            <ExtraForm key={extra.id} values={values} setValues={setValues} onSave={save} onCancel={() => { setForm(null); setError(''); }} busy={busy} />
          ) : (
            <div className="menu-extra-row" key={extra.id}>
              <div className="menu-extra-row__meta">
                <div className="menu-extra-row__name">{extra.title_ru}</div>
                <div className="menu-extra-row__sub">
                  {typeLabel(extra.type)}
                  {extra.description_ru ? ` · ${extra.description_ru}` : ''}
                </div>
              </div>
              <span className="menu-item-row__actions">
                <span className="menu-extra-row__price">{priceLabel(extra)}</span>
                <button type="button" className="admin-table__link" onClick={() => startEdit(extra)}>Изменить</button>
                {confirmId === extra.id ? (
                  <>
                    <button type="button" className="admin-table__link admin-table__link--danger" disabled={busy} onClick={() => remove(extra)}>
                      {busy ? '…' : 'Точно'}
                    </button>
                    <button type="button" className="admin-table__link" onClick={() => setConfirmId(null)}>Отмена</button>
                  </>
                ) : (
                  <button type="button" className="admin-table__link admin-table__link--danger" onClick={() => setConfirmId(extra.id)}>Удалить</button>
                )}
              </span>
            </div>
          )
        )}
      </div>

      {form === 'new' ? (
        <ExtraForm values={values} setValues={setValues} onSave={save} onCancel={() => { setForm(null); setError(''); }} busy={busy} />
      ) : (
        <div className="menu-extra-presets">
          {EXTRA_PRESETS.map((p) => (
            <button key={p.type} type="button" className="menu-add-btn" onClick={() => startCreate(p)}>+ {p.label}</button>
          ))}
        </div>
      )}
    </div>
  );
}

function ExtraForm({ values, setValues, onSave, onCancel, busy }) {
  function set(key, value) {
    setValues((v) => ({ ...v, [key]: value }));
  }
  // Preserve an unrecognised unit that already exists on the record.
  const unitKnown = UNIT_OPTIONS.some((o) => o.value === (values.unit || ''));

  return (
    <div className="menu-inline-form">
      <div className="form-row">
        <label>
          <span>Название на русском *</span>
          <input value={values.title_ru} onChange={(e) => set('title_ru', e.target.value)} placeholder="Например: Детский стол" />
        </label>
        <label>
          <span>Название на казахском</span>
          <input value={values.title_kz} onChange={(e) => set('title_kz', e.target.value)} placeholder="Мысалы: Балалар үстелі" />
        </label>
      </div>
      <div className="form-row">
        <label>
          <span>Тип условия</span>
          <select value={values.type} onChange={(e) => set('type', e.target.value)}>
            {EXTRA_PRESETS.map((p) => (
              <option key={p.type} value={p.type}>{p.label}</option>
            ))}
            {!EXTRA_PRESETS.some((p) => p.type === values.type) && (
              <option value={values.type}>{values.type}</option>
            )}
          </select>
        </label>
        <label>
          <span>Как считается цена</span>
          <select value={values.unit || ''} onChange={(e) => set('unit', e.target.value)}>
            {UNIT_OPTIONS.map((o) => (
              <option key={o.value} value={o.value}>{o.label}</option>
            ))}
            {!unitKnown && <option value={values.unit}>{values.unit}</option>}
          </select>
        </label>
      </div>
      <div className="form-row">
        <label>
          <span>{(values.unit || '').toLowerCase() === 'percent' ? 'Процент, %' : 'Сумма, ₸'}</span>
          <input type="number" min="0" inputMode="numeric" value={values.price} onChange={(e) => set('price', e.target.value)} placeholder="Например: 100 000" />
          <small className="admin-field-hint">Пусто — без доплаты</small>
        </label>
        <label>
          <span>Описание на русском</span>
          <input value={values.description_ru} onChange={(e) => set('description_ru', e.target.value)} placeholder="Необязательно" />
        </label>
      </div>
      <div className="menu-inline-form__actions">
        <button type="button" className="btn btn--gold btn--sm" disabled={busy} onClick={onSave}>
          {busy ? 'Сохранение…' : 'Сохранить'}
        </button>
        <button type="button" className="btn btn--outline btn--sm" onClick={onCancel} disabled={busy}>Отмена</button>
      </div>
    </div>
  );
}
