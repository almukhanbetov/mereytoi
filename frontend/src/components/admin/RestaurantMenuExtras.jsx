'use client';

import { useState } from 'react';
import { adminApi } from '@/lib/adminApi';
import { formatPrice } from '@/lib/format';

const EMPTY = { type: 'service', title_ru: '', title_kz: '', price: 0, unit: '', description_ru: '', description_kz: '', sort_order: 0 };

// Brief section 5's own suggested list — presets only, never a fixed
// enum: Type/Unit stay free-form strings on the backend (matches how
// Event.Type/Booking.Status are already modeled there), so "другие
// условия" is just "type: other" with a title the admin writes themselves.
const EXTRA_PRESETS = [
  { type: 'kids_table', label: 'Детский стол' },
  { type: 'artists_table', label: 'Стол артистов' },
  { type: 'service_fee', label: 'Сервисный сбор' },
  { type: 'rental', label: 'Аренда' },
  { type: 'corkage', label: 'Пробковый сбор' },
  { type: 'other', label: 'Другое условие' },
];

/** Brief section 5 — extras CRUD, reusing the existing
 * ListingMenuExtra API built in the prior stage. */
export default function RestaurantMenuExtras({ listingId, menu, refresh }) {
  const extras = [...(menu.extras || [])].sort((a, b) => a.sort_order - b.sort_order);
  const [form, setForm] = useState(null); // null | 'new' | extra.id being edited
  const [values, setValues] = useState(EMPTY);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  function startCreate(preset) {
    setValues({ ...EMPTY, type: preset?.type || 'service', title_ru: preset?.label || '', title_kz: preset?.label || '', sort_order: extras.length });
    setForm('new');
    setError('');
  }
  function startEdit(extra) {
    setValues({ ...extra });
    setForm(extra.id);
    setError('');
  }

  async function save() {
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
    if (!window.confirm(`Удалить «${extra.title_ru}»?`)) return;
    try {
      await adminApi.deleteExtra(listingId, menu.id, extra.id);
      await refresh();
    } catch (err) {
      alert(err.message || 'Не удалось удалить условие');
    }
  }

  return (
    <div style={{ marginTop: 18 }}>
      <h4 style={{ margin: '0 0 10px', fontSize: 14 }}>Дополнительно</h4>

      {extras.length === 0 && form === null && <p className="admin-table__empty">Дополнительных условий нет</p>}

      <div className="admin-inline-list">
        {extras.map((extra) =>
          form === extra.id ? (
            <ExtraForm key={extra.id} values={values} setValues={setValues} onSave={save} onCancel={() => setForm(null)} busy={busy} error={error} />
          ) : (
            <div className="admin-inline-row" key={extra.id}>
              <span>
                {extra.title_ru}
                {extra.price > 0 ? ` — ${formatPrice(extra.price)}${extra.unit ? ` / ${extra.unit}` : ''}` : ''}
              </span>
              <span className="admin-inline-row__actions">
                <button type="button" className="admin-table__link" onClick={() => startEdit(extra)}>Изменить</button>
                <button type="button" className="admin-table__link admin-table__link--danger" onClick={() => remove(extra)}>Удалить</button>
              </span>
            </div>
          )
        )}
      </div>

      {form === 'new' ? (
        <ExtraForm values={values} setValues={setValues} onSave={save} onCancel={() => setForm(null)} busy={busy} error={error} />
      ) : (
        <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>
          {EXTRA_PRESETS.map((p) => (
            <button key={p.type} type="button" className="admin-table__link" onClick={() => startCreate(p)}>+ {p.label}</button>
          ))}
        </div>
      )}
    </div>
  );
}

function ExtraForm({ values, setValues, onSave, onCancel, busy, error }) {
  function set(key, value) {
    setValues((v) => ({ ...v, [key]: value }));
  }
  return (
    <div className="admin-section-block">
      <div className="form-row">
        <label>
          <span>Название (рус)</span>
          <input value={values.title_ru} onChange={(e) => set('title_ru', e.target.value)} />
        </label>
        <label>
          <span>Название (қаз)</span>
          <input value={values.title_kz} onChange={(e) => set('title_kz', e.target.value)} />
        </label>
      </div>
      <div className="form-row">
        <label>
          <span>Цена, ₸</span>
          <input type="number" min="0" value={values.price} onChange={(e) => set('price', e.target.value)} />
        </label>
        <label>
          <span>Единица (per_guest / per_item / flat)</span>
          <input value={values.unit} onChange={(e) => set('unit', e.target.value)} />
        </label>
      </div>
      <label>
        <span>Описание (рус)</span>
        <textarea rows="2" value={values.description_ru} onChange={(e) => set('description_ru', e.target.value)} />
      </label>
      {error && <p className="admin-login__error">{error}</p>}
      <div style={{ display: 'flex', gap: 10 }}>
        <button type="button" className="btn btn--gold btn--sm" disabled={busy} onClick={onSave}>Сохранить</button>
        <button type="button" className="btn btn--outline btn--sm" onClick={onCancel}>Отмена</button>
      </div>
    </div>
  );
}
