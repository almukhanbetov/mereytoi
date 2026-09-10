'use client';

import { useRef, useState } from 'react';
import { adminApi } from '@/lib/adminApi';
import { formatPrice } from '@/lib/format';
import { mediaUrl } from '@/lib/media';

// capacity/price/sort_order are kept as *strings* in form state so an
// unset value shows the placeholder rather than a meaningless "0" — they
// are coerced back to numbers only on save (payloadFromForm below).
const EMPTY = {
  name_ru: '', name_kz: '', description_ru: '', description_kz: '',
  capacity: '', price: '', image_urls: [], is_active: true, sort_order: 0,
};

function sortByOrder(list) {
  return [...list].sort((a, b) => a.sort_order - b.sort_order);
}

// Existing hall row -> editable form values (0 -> '' for the numeric
// fields so the input shows its placeholder, existing photos preserved).
function formFromHall(hall) {
  return {
    name_ru: hall.name_ru || '',
    name_kz: hall.name_kz || '',
    description_ru: hall.description_ru || '',
    description_kz: hall.description_kz || '',
    capacity: hall.capacity ? String(hall.capacity) : '',
    price: hall.price ? String(hall.price) : '',
    image_urls: hall.image_urls || [],
    is_active: hall.is_active,
    sort_order: hall.sort_order ?? 0,
  };
}

function payloadFromForm(f) {
  return {
    name_ru: f.name_ru.trim(),
    name_kz: f.name_kz.trim(),
    description_ru: f.description_ru,
    description_kz: f.description_kz,
    capacity: Number(f.capacity) || 0,
    price: Number(f.price) || 0,
    image_urls: f.image_urls || [],
    is_active: f.is_active,
    sort_order: Number(f.sort_order) || 0,
  };
}

// ListingHallHandler.Update replaces the whole row (non-PATCH contract),
// so toggle-active / reorder / duplicate must resend every other field
// unchanged — same approach RestaurantMenusTab already uses for menus.
function payloadFromRow(h) {
  return {
    name_ru: h.name_ru,
    name_kz: h.name_kz,
    description_ru: h.description_ru || '',
    description_kz: h.description_kz || '',
    capacity: h.capacity || 0,
    price: h.price || 0,
    image_urls: h.image_urls || [],
    is_active: h.is_active,
    sort_order: h.sort_order ?? 0,
  };
}

/** Admin UX for restaurant/venue halls. Frontend-only — the halls API
 * (createHall/updateHall/deleteHall in adminApi.js), the ListingHall
 * model and every other backend contract are untouched.
 *
 * `halls`/`refresh` come from the parent tab shell (RestaurantAdminTabs):
 * the Menus tab's own hall-picker needs the same up-to-date list, so both
 * tabs share one source of truth. `refresh()` re-reads the listing tree —
 * the list here updates in place, never a full page reload.
 *
 * "Дублировать" has no dedicated backend endpoint (none needed) — it
 * composes the existing createHall primitive client-side, exactly like
 * RestaurantMenusTab's own "Дублировать меню". */
export default function RestaurantHallsTab({ listingId, halls, refresh }) {
  const sorted = sortByOrder(halls);
  const [editingId, setEditingId] = useState(null); // null | 'new' | hall id
  const [form, setForm] = useState(EMPTY);
  const [saving, setSaving] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState('');
  const [savedTick, setSavedTick] = useState(false);
  const [busyId, setBusyId] = useState(null);         // hall mid toggle/reorder/delete
  const [duplicatingId, setDuplicatingId] = useState(null);
  const [confirmingId, setConfirmingId] = useState(null); // hall pending delete confirm

  const isFormOpen = editingId !== null;

  function startCreate() {
    setForm({ ...EMPTY, sort_order: sorted.length });
    setEditingId('new');
    setError('');
    setSavedTick(false);
  }
  function startEdit(hall) {
    setForm(formFromHall(hall));
    setEditingId(hall.id);
    setError('');
    setSavedTick(false);
  }
  function cancel() {
    setEditingId(null);
    setError('');
  }

  async function handleFilesList(fileList) {
    const files = Array.from(fileList || []);
    if (!files.length) return;
    setUploading(true);
    setError('');
    try {
      const urls = await adminApi.uploadImages(files);
      setForm((f) => ({ ...f, image_urls: [...(f.image_urls || []), ...urls] }));
    } catch (err) {
      setError(err.message || 'Не удалось загрузить фото');
    } finally {
      setUploading(false);
    }
  }
  function removeImage(url) {
    setForm((f) => ({ ...f, image_urls: f.image_urls.filter((u) => u !== url) }));
  }

  async function save() {
    if (!form.name_ru.trim() || !form.name_kz.trim()) {
      setError('Укажите название зала на русском и казахском');
      return;
    }
    setSaving(true);
    setError('');
    try {
      const payload = payloadFromForm(form);
      if (editingId === 'new') await adminApi.createHall(listingId, payload);
      else await adminApi.updateHall(listingId, editingId, payload);
      await refresh();
      setEditingId(null);
      setSavedTick(true);
      setTimeout(() => setSavedTick(false), 2600);
    } catch (err) {
      setError(err.message || 'Не удалось сохранить зал');
    } finally {
      setSaving(false);
    }
  }

  async function toggleActive(hall) {
    setBusyId(hall.id);
    setError('');
    try {
      await adminApi.updateHall(listingId, hall.id, { ...payloadFromRow(hall), is_active: !hall.is_active });
      await refresh();
    } catch (err) {
      setError(err.message || 'Не удалось изменить статус зала');
    } finally {
      setBusyId(null);
    }
  }

  async function remove(hall) {
    setBusyId(hall.id);
    setError('');
    try {
      await adminApi.deleteHall(listingId, hall.id);
      await refresh();
      setConfirmingId(null);
    } catch (err) {
      setError(err.message || 'Не удалось удалить зал');
    } finally {
      setBusyId(null);
    }
  }

  async function move(hall, direction) {
    const idx = sorted.findIndex((h) => h.id === hall.id);
    const swapIdx = idx + direction;
    if (swapIdx < 0 || swapIdx >= sorted.length) return;
    const a = sorted[idx];
    const b = sorted[swapIdx];
    setBusyId(hall.id);
    setError('');
    try {
      await Promise.all([
        adminApi.updateHall(listingId, a.id, { ...payloadFromRow(a), sort_order: b.sort_order }),
        adminApi.updateHall(listingId, b.id, { ...payloadFromRow(b), sort_order: a.sort_order }),
      ]);
      await refresh();
    } catch (err) {
      setError(err.message || 'Не удалось изменить порядок');
    } finally {
      setBusyId(null);
    }
  }

  async function duplicate(hall) {
    setDuplicatingId(hall.id);
    setError('');
    try {
      await adminApi.createHall(listingId, {
        ...payloadFromRow(hall),
        name_ru: `${hall.name_ru} (копия)`,
        name_kz: hall.name_kz ? `${hall.name_kz} (көшірме)` : `${hall.name_ru} (копия)`,
        is_active: false,
        sort_order: sorted.length,
      });
      await refresh();
    } catch (err) {
      setError(err.message || 'Не удалось дублировать зал');
    } finally {
      setDuplicatingId(null);
    }
  }

  return (
    <div className="hall-admin">
      <div className="admin-tab-head">
        <div>
          <h2 className="admin-section-title" style={{ margin: 0 }}>Залы ресторана</h2>
          <p className="admin-subtitle">
            Создавайте несколько залов, указывайте вместимость, отдельную цену и фотографии.
          </p>
        </div>
        {!isFormOpen && (
          <button type="button" className="btn btn--gold btn--sm" onClick={startCreate}>+ Добавить зал</button>
        )}
      </div>

      {savedTick && <p className="admin-banner admin-banner--ok">Изменения сохранены</p>}
      {error && !isFormOpen && <p className="admin-banner admin-banner--error">{error}</p>}

      {isFormOpen && (
        <HallForm
          mode={editingId === 'new' ? 'create' : 'edit'}
          form={form}
          setForm={setForm}
          onSave={save}
          onCancel={cancel}
          saving={saving}
          uploading={uploading}
          error={error}
          onFilesList={handleFilesList}
          onRemoveImage={removeImage}
        />
      )}

      {/* The hall list stays visible even while the form is open — the
          admin should always be able to see whether halls exist and how
          many (brief section 6). Only the truly-empty, not-yet-creating
          state swaps in the illustrated empty card instead. */}
      {sorted.length === 0 && editingId !== 'new' ? (
        <div className="admin-empty">
          <div className="admin-empty__icon" aria-hidden="true">🏛️</div>
          <div className="admin-empty__title">Залов пока нет</div>
          <p className="admin-empty__text">
            Добавьте первый зал ресторана, чтобы клиент мог выбрать подходящий вариант.
          </p>
          <button type="button" className="btn btn--gold btn--sm" onClick={startCreate}>+ Добавить первый зал</button>
        </div>
      ) : sorted.length > 0 && (
        <>
          {isFormOpen && <p className="admin-subtitle" style={{ margin: '4px 0 12px' }}>Все залы ресторана — {sorted.length}</p>}
          <div className="admin-card-grid admin-card-grid--halls">
            {sorted.map((hall, i) => (
              <HallCard
                key={hall.id}
                hall={hall}
                index={i}
                total={sorted.length}
                editing={editingId === hall.id}
                busy={busyId === hall.id}
                duplicating={duplicatingId === hall.id}
                confirming={confirmingId === hall.id}
                onEdit={() => startEdit(hall)}
                onDuplicate={() => duplicate(hall)}
                onToggle={() => toggleActive(hall)}
                onAskDelete={() => setConfirmingId(hall.id)}
                onCancelDelete={() => setConfirmingId(null)}
                onConfirmDelete={() => remove(hall)}
                onMove={(dir) => move(hall, dir)}
              />
            ))}
          </div>
        </>
      )}
    </div>
  );
}

function HallCard({
  hall, index, total, editing, busy, duplicating, confirming,
  onEdit, onDuplicate, onToggle, onAskDelete, onCancelDelete, onConfirmDelete, onMove,
}) {
  const cover = hall.image_urls?.[0];
  const hasOwnPrice = hall.price > 0;

  return (
    <div className={`admin-card admin-card--hall${hall.is_active ? '' : ' admin-card--inactive'}${editing ? ' admin-card--editing' : ''}`}>
      <div className="admin-card__cover">
        {cover
          ? <img src={mediaUrl(cover)} alt="" />
          : <span className="admin-card__cover-empty" aria-hidden="true">🏛️</span>}
        <span className={`admin-card__badge${hall.is_active ? '' : ' admin-card__badge--off'}`}>
          {hall.is_active ? 'Активен' : 'Скрыт'}
        </span>
        {hall.image_urls?.length > 1 && (
          <span className="admin-card__cover-count">{hall.image_urls.length} фото</span>
        )}
      </div>

      <div className="admin-card__body">
        <h3 className="admin-card__title">{hall.name_ru || '— без названия —'}</h3>
        {hall.name_kz && hall.name_kz !== hall.name_ru && (
          <p className="admin-card__subtitle">{hall.name_kz}</p>
        )}
        <div className="admin-card__facts">
          <span>
            <b>{hall.capacity ? `${hall.capacity} гостей` : '—'}</b>
            <small>вместимость</small>
          </span>
          <span>
            <b>{hasOwnPrice ? formatPrice(hall.price) : 'Цена ресторана'}</b>
            <small>{hasOwnPrice ? 'цена зала' : 'своя цена не задана'}</small>
          </span>
          <span>
            <b>{index + 1}</b>
            <small>порядок</small>
          </span>
        </div>
      </div>

      {confirming ? (
        <div className="admin-card__confirm">
          <span>Удалить зал «{hall.name_ru}»? Прошлые заявки, где он выбран, сохранят его название.</span>
          <div className="admin-card__confirm-actions">
            <button type="button" className="admin-table__link admin-table__link--danger" disabled={busy} onClick={onConfirmDelete}>
              {busy ? 'Удаляем…' : 'Да, удалить'}
            </button>
            <button type="button" className="admin-table__link" onClick={onCancelDelete}>Отмена</button>
          </div>
        </div>
      ) : (
        <div className="admin-card__actions admin-card__actions--hall">
          <button type="button" className="admin-table__link" onClick={onEdit}>Редактировать</button>
          <button type="button" className="admin-table__link" disabled={duplicating} onClick={onDuplicate}>
            {duplicating ? 'Копируем…' : 'Дублировать'}
          </button>
          <button type="button" className="admin-table__link" disabled={busy} onClick={onToggle}>
            {hall.is_active ? 'Скрыть' : 'Активировать'}
          </button>
          <button type="button" className="admin-table__link admin-table__link--danger" onClick={onAskDelete}>Удалить</button>
          <span className="admin-card__order">
            <button type="button" className="admin-icon-btn" disabled={index === 0 || busy} onClick={() => onMove(-1)} aria-label="Переместить выше">↑</button>
            <button type="button" className="admin-icon-btn" disabled={index === total - 1 || busy} onClick={() => onMove(1)} aria-label="Переместить ниже">↓</button>
          </span>
        </div>
      )}
    </div>
  );
}

function HallForm({ mode, form, setForm, onSave, onCancel, saving, uploading, error, onFilesList, onRemoveImage }) {
  function set(key, value) {
    setForm((f) => ({ ...f, [key]: value }));
  }
  const busy = saving || uploading;

  return (
    <form
      className="contacts__form admin-form-card"
      onSubmit={(e) => { e.preventDefault(); onSave(); }}
    >
      <div className="admin-form-card__head">
        <h3 className="admin-form-card__title">{mode === 'create' ? 'Новый зал' : 'Редактирование зала'}</h3>
      </div>

      <fieldset className="admin-fieldset">
        <legend className="admin-fieldset__legend">Основная информация</legend>
        <div className="form-row">
          <label>
            <span>Название на русском *</span>
            <input value={form.name_ru} onChange={(e) => set('name_ru', e.target.value)} placeholder="Например: Большой зал" required />
          </label>
          <label>
            <span>Название на казахском</span>
            <input value={form.name_kz} onChange={(e) => set('name_kz', e.target.value)} placeholder="Мысалы: Үлкен зал" required />
          </label>
        </div>
        <div className="form-row">
          <label>
            <span>Описание на русском</span>
            <textarea rows="3" value={form.description_ru} onChange={(e) => set('description_ru', e.target.value)} placeholder="Атмосфера, особенности, вид…" />
          </label>
          <label>
            <span>Описание на казахском</span>
            <textarea rows="3" value={form.description_kz} onChange={(e) => set('description_kz', e.target.value)} placeholder="Атмосферасы, ерекшеліктері…" />
          </label>
        </div>
      </fieldset>

      <fieldset className="admin-fieldset">
        <legend className="admin-fieldset__legend">Параметры</legend>
        <div className="form-row">
          <label>
            <span>Вместимость гостей</span>
            <input type="number" min="0" inputMode="numeric" value={form.capacity} onChange={(e) => set('capacity', e.target.value)} placeholder="Например: 250" />
            <small className="admin-field-hint">Например: 250 гостей</small>
          </label>
          <label>
            <span>Цена зала, ₸</span>
            <input type="number" min="0" inputMode="numeric" value={form.price} onChange={(e) => set('price', e.target.value)} placeholder="0" />
            <small className="admin-field-hint">0 — использовать базовую цену ресторана</small>
          </label>
        </div>
        <div className="form-row">
          <label>
            <span>Порядок отображения</span>
            <input type="number" min="0" inputMode="numeric" value={form.sort_order} onChange={(e) => set('sort_order', e.target.value)} placeholder="0" />
            <small className="admin-field-hint">Меньшее значение показывается выше</small>
          </label>
          <span aria-hidden="true" />
        </div>
        <div className="admin-field-switch">
          <label className="admin-switch">
            <input type="checkbox" checked={form.is_active} onChange={(e) => set('is_active', e.target.checked)} />
            <span className="admin-switch__track" aria-hidden="true" />
            <span className="admin-switch__label">
              <b>Активен</b>
              <small>Зал показывается клиентам</small>
            </span>
          </label>
        </div>
      </fieldset>

      <fieldset className="admin-fieldset">
        <legend className="admin-fieldset__legend">Фото зала</legend>
        <HallPhotoUploader images={form.image_urls} uploading={uploading} onFilesList={onFilesList} onRemove={onRemoveImage} />
      </fieldset>

      {error && <p className="admin-banner admin-banner--error" style={{ marginBottom: 0 }}>{error}</p>}

      <div className="admin-form-card__actions">
        <button type="submit" className="btn btn--gold" disabled={busy}>
          {saving
            ? <><span className="admin-spinner" aria-hidden="true" /> Сохранение…</>
            : (mode === 'create' ? 'Сохранить зал' : 'Сохранить изменения')}
        </button>
        <button type="button" className="btn btn--outline" onClick={onCancel} disabled={saving}>Отмена</button>
      </div>
    </form>
  );
}

function HallPhotoUploader({ images, uploading, onFilesList, onRemove }) {
  const inputRef = useRef(null);
  const [dragging, setDragging] = useState(false);

  function handleDrop(e) {
    e.preventDefault();
    setDragging(false);
    if (e.dataTransfer?.files?.length) onFilesList(e.dataTransfer.files);
  }

  return (
    <div>
      <div
        className={`admin-dropzone${dragging ? ' is-dragging' : ''}`}
        role="button"
        tabIndex={0}
        onClick={() => inputRef.current?.click()}
        onKeyDown={(e) => {
          if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); inputRef.current?.click(); }
        }}
        onDragOver={(e) => { e.preventDefault(); setDragging(true); }}
        onDragLeave={() => setDragging(false)}
        onDrop={handleDrop}
      >
        <span className="admin-dropzone__icon" aria-hidden="true">🖼️</span>
        <span className="admin-dropzone__title">Перетащите фото сюда</span>
        <span className="admin-dropzone__hint">
          или <span className="admin-dropzone__browse">выберите файл</span> — PNG, JPG, WEBP, можно несколько
        </span>
        <input
          ref={inputRef}
          type="file"
          accept="image/png,image/jpeg,image/webp,image/gif"
          multiple
          onChange={(e) => { onFilesList(e.target.files); e.target.value = ''; }}
        />
      </div>

      {uploading && (
        <p className="admin-upload-status" style={{ marginTop: 12 }}>
          <span className="admin-spinner" aria-hidden="true" /> Загружаем фото…
        </p>
      )}

      {images?.length > 0 && (
        <div className="admin-image-grid" style={{ marginTop: 14 }}>
          {images.map((url, i) => (
            <div className="admin-image-thumb" key={url}>
              <img src={mediaUrl(url)} alt="" />
              {i === 0 && <span className="admin-image-thumb__badge">Обложка</span>}
              <button type="button" className="admin-image-thumb__remove" onClick={() => onRemove(url)} aria-label="Удалить фото">✕</button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
