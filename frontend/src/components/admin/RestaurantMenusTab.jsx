'use client';

import { useState } from 'react';
import { adminApi } from '@/lib/adminApi';
import { formatPrice } from '@/lib/format';
import RestaurantMenuSections from './RestaurantMenuSections';
import RestaurantMenuExtras from './RestaurantMenuExtras';

// price_per_guest / sort_order are kept as strings in form state so an
// unset value shows its placeholder rather than a literal "0"; min/max
// guests already were '' in the original. Coerced back on save.
const EMPTY_MENU = {
  hall_id: '', name_ru: '', name_kz: '', description_ru: '', description_kz: '',
  price_per_guest: '', min_guests: '', max_guests: '', is_active: true, sort_order: 0,
  valid_from: '', valid_until: '',
};

function sortByOrder(list) {
  return [...list].sort((a, b) => a.sort_order - b.sort_order);
}

// Form values -> create/update payload. Contract unchanged from the
// original tab: hall_id '' -> null, guests '' -> null, dates '' -> null,
// date string -> ISO.
function menuFormToPayload(f) {
  return {
    hall_id: f.hall_id === '' ? null : Number(f.hall_id),
    name_ru: f.name_ru.trim(),
    name_kz: f.name_kz.trim(),
    description_ru: f.description_ru,
    description_kz: f.description_kz,
    price_per_guest: Number(f.price_per_guest) || 0,
    min_guests: f.min_guests === '' ? null : Number(f.min_guests),
    max_guests: f.max_guests === '' ? null : Number(f.max_guests),
    is_active: f.is_active,
    sort_order: Number(f.sort_order) || 0,
    valid_from: f.valid_from ? new Date(f.valid_from).toISOString() : null,
    valid_until: f.valid_until ? new Date(f.valid_until).toISOString() : null,
  };
}

// Existing row -> update payload. UpdateMenu replaces the whole row
// (non-PATCH contract), so toggle-active / reorder resend every field
// unchanged — same as the original tab did.
function menuRowToPayload(m) {
  return {
    hall_id: m.hall_id ?? null,
    name_ru: m.name_ru, name_kz: m.name_kz,
    description_ru: m.description_ru || '', description_kz: m.description_kz || '',
    price_per_guest: m.price_per_guest,
    min_guests: m.min_guests ?? null, max_guests: m.max_guests ?? null,
    is_active: m.is_active, sort_order: m.sort_order,
    valid_from: m.valid_from ?? null, valid_until: m.valid_until ?? null,
  };
}

function formFromMenu(menu) {
  return {
    hall_id: menu.hall_id ?? '',
    name_ru: menu.name_ru || '',
    name_kz: menu.name_kz || '',
    description_ru: menu.description_ru || '',
    description_kz: menu.description_kz || '',
    price_per_guest: menu.price_per_guest ? String(menu.price_per_guest) : '',
    min_guests: menu.min_guests ?? '',
    max_guests: menu.max_guests ?? '',
    is_active: menu.is_active,
    sort_order: menu.sort_order ?? 0,
    valid_from: menu.valid_from ? menu.valid_from.slice(0, 10) : '',
    valid_until: menu.valid_until ? menu.valid_until.slice(0, 10) : '',
  };
}

function fmtDate(iso) {
  if (!iso) return null;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  return d.toLocaleDateString('ru-RU', { day: '2-digit', month: '2-digit', year: 'numeric' });
}

function guestsLabel(min, max) {
  if (min && max) return `от ${min} до ${max}`;
  if (min) return `от ${min}`;
  if (max) return `до ${max}`;
  return 'без ограничения';
}

/** Admin UX for restaurant/venue banquet menus. Frontend-only — every
 * ListingMenu / section / item / extra API call, payload and the models
 * behind them are untouched; this only reorganises the screen.
 *
 * `menus`/`halls`/`refresh` come from the parent tab shell
 * (RestaurantAdminTabs) so switching tabs never shows a stale snapshot.
 * `refresh()` re-reads the whole listing tree after every mutation — the
 * cards update in place, never a full page reload.
 *
 * "Дублировать" has no dedicated backend endpoint (none needed): it
 * composes the existing createMenu + createSection/createItem/createExtra
 * primitives, exactly as the original tab did. */
export default function RestaurantMenusTab({ listingId, menus: rawMenus, halls, refresh }) {
  const menus = sortByOrder(rawMenus);
  const [openId, setOpenId] = useState(null);        // menu whose "состав" builder is shown
  const [creating, setCreating] = useState(false);
  const [editingId, setEditingId] = useState(null);
  const [form, setForm] = useState(EMPTY_MENU);
  const [saving, setSaving] = useState(false);
  const [duplicatingId, setDuplicatingId] = useState(null);
  const [confirmingId, setConfirmingId] = useState(null);
  const [busyId, setBusyId] = useState(null);
  const [error, setError] = useState('');
  const [savedTick, setSavedTick] = useState(false);

  const anyFormOpen = creating || editingId !== null;
  const openMenu = menus.find((m) => m.id === openId) || null;

  function startCreate() {
    setForm({ ...EMPTY_MENU, sort_order: menus.length });
    setCreating(true);
    setEditingId(null);
    setOpenId(null);
    setError('');
    setSavedTick(false);
  }
  function startEdit(menu) {
    setForm(formFromMenu(menu));
    setEditingId(menu.id);
    setCreating(false);
    setOpenId(null);
    setError('');
    setSavedTick(false);
  }
  function cancelForm() {
    setCreating(false);
    setEditingId(null);
    setError('');
  }
  function toggleBuilder(menuId) {
    setOpenId((prev) => (prev === menuId ? null : menuId));
    setEditingId(null);
    setCreating(false);
  }

  function validate(f) {
    if (!f.name_ru.trim() || !f.name_kz.trim()) return 'Укажите название меню на русском и казахском';
    if (f.valid_from && f.valid_until && f.valid_until < f.valid_from) {
      return 'Дата «действует по» не может быть раньше даты «действует с»';
    }
    return '';
  }

  async function save() {
    const v = validate(form);
    if (v) { setError(v); return; }
    setSaving(true);
    setError('');
    try {
      if (creating) await adminApi.createMenu(listingId, menuFormToPayload(form));
      else await adminApi.updateMenu(listingId, editingId, menuFormToPayload(form));
      await refresh();
      setCreating(false);
      setEditingId(null);
      setSavedTick(true);
      setTimeout(() => setSavedTick(false), 2600);
    } catch (err) {
      setError(err.message || 'Не удалось сохранить меню');
    } finally {
      setSaving(false);
    }
  }

  async function toggleActive(menu) {
    setBusyId(menu.id);
    setError('');
    try {
      await adminApi.updateMenu(listingId, menu.id, { ...menuRowToPayload(menu), is_active: !menu.is_active });
      await refresh();
    } catch (err) {
      setError(err.message || 'Не удалось изменить статус меню');
    } finally {
      setBusyId(null);
    }
  }

  async function move(menu, direction) {
    const idx = menus.findIndex((m) => m.id === menu.id);
    const swapIdx = idx + direction;
    if (swapIdx < 0 || swapIdx >= menus.length) return;
    const a = menus[idx];
    const b = menus[swapIdx];
    setBusyId(menu.id);
    setError('');
    try {
      await Promise.all([
        adminApi.updateMenu(listingId, a.id, { ...menuRowToPayload(a), sort_order: b.sort_order }),
        adminApi.updateMenu(listingId, b.id, { ...menuRowToPayload(b), sort_order: a.sort_order }),
      ]);
      await refresh();
    } catch (err) {
      setError(err.message || 'Не удалось изменить порядок меню');
    } finally {
      setBusyId(null);
    }
  }

  async function remove(menu) {
    setBusyId(menu.id);
    setError('');
    try {
      await adminApi.deleteMenu(listingId, menu.id);
      await refresh();
      if (openId === menu.id) setOpenId(null);
      setConfirmingId(null);
    } catch (err) {
      setError(err.message || 'Не удалось удалить меню');
    } finally {
      setBusyId(null);
    }
  }

  // Duplicate — identical behaviour to the original tab: a new *inactive*
  // menu, then every section/item/extra recreated from the loaded tree in
  // the same order, via the existing CRUD calls only.
  async function duplicate(menu) {
    setDuplicatingId(menu.id);
    setError('');
    try {
      const { menu: created } = await adminApi.createMenu(listingId, {
        hall_id: menu.hall_id ?? null,
        name_ru: `${menu.name_ru} — копия`,
        name_kz: menu.name_kz ? `${menu.name_kz} — көшірме` : `${menu.name_ru} — копия`,
        description_ru: menu.description_ru || '', description_kz: menu.description_kz || '',
        price_per_guest: menu.price_per_guest,
        min_guests: menu.min_guests ?? null, max_guests: menu.max_guests ?? null,
        is_active: false, sort_order: menus.length,
        valid_from: menu.valid_from ?? null, valid_until: menu.valid_until ?? null,
      });

      const sortedSections = [...(menu.sections || [])].sort((a, b) => a.sort_order - b.sort_order);
      for (const section of sortedSections) {
        const { section: newSection } = await adminApi.createSection(listingId, created.id, {
          title_ru: section.title_ru, title_kz: section.title_kz, sort_order: section.sort_order,
        });
        const sortedItems = [...(section.items || [])].sort((a, b) => a.sort_order - b.sort_order);
        for (const item of sortedItems) {
          await adminApi.createItem(listingId, created.id, newSection.id, {
            name_ru: item.name_ru, name_kz: item.name_kz,
            description_ru: item.description_ru || '', description_kz: item.description_kz || '',
            quantity_text: item.quantity_text || '', sort_order: item.sort_order,
          });
        }
      }

      const sortedExtras = [...(menu.extras || [])].sort((a, b) => a.sort_order - b.sort_order);
      for (const extra of sortedExtras) {
        await adminApi.createExtra(listingId, created.id, {
          type: extra.type, title_ru: extra.title_ru, title_kz: extra.title_kz,
          price: extra.price, unit: extra.unit || '',
          description_ru: extra.description_ru || '', description_kz: extra.description_kz || '', sort_order: extra.sort_order,
        });
      }

      await refresh();
      setOpenId(created.id);
    } catch (err) {
      setError(err.message || 'Не удалось дублировать меню');
    } finally {
      setDuplicatingId(null);
    }
  }

  return (
    <div className="menu-admin">
      <div className="admin-tab-head">
        <div>
          <h2 className="admin-section-title" style={{ margin: 0 }}>Банкетные меню</h2>
          <p className="admin-subtitle">
            Создавайте несколько вариантов меню для разных залов, количества гостей и бюджета.
          </p>
        </div>
        {!anyFormOpen && (
          <button type="button" className="btn btn--gold btn--sm" onClick={startCreate}>+ Добавить меню</button>
        )}
      </div>

      {savedTick && <p className="admin-banner admin-banner--ok">Меню сохранено</p>}
      {error && !anyFormOpen && <p className="admin-banner admin-banner--error">{error}</p>}

      {creating && (
        <MenuForm
          mode="create"
          form={form}
          setForm={setForm}
          halls={halls}
          onSave={save}
          onCancel={cancelForm}
          saving={saving}
          error={error}
        />
      )}

      {menus.length === 0 && !creating ? (
        <div className="admin-empty">
          <div className="admin-empty__icon" aria-hidden="true">🍽️</div>
          <div className="admin-empty__title">Меню пока нет</div>
          <p className="admin-empty__text">Добавьте первое банкетное меню ресторана.</p>
          <button type="button" className="btn btn--gold btn--sm" onClick={startCreate}>+ Добавить первое меню</button>
        </div>
      ) : menus.length > 0 && (
        <>
          {creating && <p className="admin-subtitle" style={{ margin: '4px 0 12px' }}>Все меню ресторана — {menus.length}</p>}

          <div className="admin-card-grid admin-card-grid--menus">
            {menus.map((menu, i) => (
              <MenuCard
                key={menu.id}
                menu={menu}
                hall={halls.find((h) => h.id === menu.hall_id) || null}
                index={i}
                total={menus.length}
                editing={editingId === menu.id}
                expanded={openId === menu.id}
                busy={busyId === menu.id}
                duplicating={duplicatingId === menu.id}
                confirming={confirmingId === menu.id}
                onEdit={() => startEdit(menu)}
                onToggleBuilder={() => toggleBuilder(menu.id)}
                onDuplicate={() => duplicate(menu)}
                onToggle={() => toggleActive(menu)}
                onAskDelete={() => setConfirmingId(menu.id)}
                onCancelDelete={() => setConfirmingId(null)}
                onConfirmDelete={() => remove(menu)}
                onMove={(dir) => move(menu, dir)}
              />
            ))}
          </div>

          {editingId !== null && (
            <MenuForm
              mode="edit"
              form={form}
              setForm={setForm}
              halls={halls}
              onSave={save}
              onCancel={cancelForm}
              saving={saving}
              error={error}
            />
          )}

          {editingId === null && openMenu && (
            <div className="menu-builder">
              <div className="menu-builder__head">
                <h3 className="menu-builder__title">«{openMenu.name_ru}» — состав меню</h3>
                <button type="button" className="admin-table__link" onClick={() => setOpenId(null)}>Свернуть</button>
              </div>
              <RestaurantMenuSections listingId={listingId} menu={openMenu} refresh={refresh} />
              <RestaurantMenuExtras listingId={listingId} menu={openMenu} refresh={refresh} />
            </div>
          )}
        </>
      )}
    </div>
  );
}

function MenuCard({
  menu, hall, index, total, editing, expanded, busy, duplicating, confirming,
  onEdit, onToggleBuilder, onDuplicate, onToggle, onAskDelete, onCancelDelete, onConfirmDelete, onMove,
}) {
  const sectionCount = (menu.sections || []).length;
  const itemCount = (menu.sections || []).reduce((n, s) => n + (s.items || []).length, 0);
  const extraCount = (menu.extras || []).length;
  const from = fmtDate(menu.valid_from);
  const until = fmtDate(menu.valid_until);
  const period = from || until ? `${from || '…'} — ${until || '…'}` : null;

  return (
    <div className={`admin-card admin-card--menu${menu.is_active ? '' : ' admin-card--inactive'}${editing || expanded ? ' admin-card--editing' : ''}`}>
      <div className="admin-card__head">
        <div>
          <h3 className="admin-card__title">{menu.name_ru || '— без названия —'}</h3>
          {menu.name_kz && menu.name_kz !== menu.name_ru && <p className="admin-card__subtitle">{menu.name_kz}</p>}
        </div>
        <div className="menu-card__head-right">
          <span className={`admin-card__badge${menu.is_active ? '' : ' admin-card__badge--off'}`}>
            {menu.is_active ? 'Активно' : 'Скрыто'}
          </span>
          <span className="admin-card__order">
            <button type="button" className="admin-icon-btn admin-icon-btn--sm" disabled={index === 0 || busy} onClick={() => onMove(-1)} aria-label="Переместить выше">↑</button>
            <button type="button" className="admin-icon-btn admin-icon-btn--sm" disabled={index === total - 1 || busy} onClick={() => onMove(1)} aria-label="Переместить ниже">↓</button>
          </span>
        </div>
      </div>

      <dl className="menu-card__spec">
        <dt>Цена</dt>
        <dd>{menu.price_per_guest > 0 ? `${formatPrice(menu.price_per_guest)} / гость` : 'не указана'}</dd>
        <dt>Зал</dt>
        <dd>{hall ? hall.name_ru : 'Любой зал'}</dd>
        <dt>Гостей</dt>
        <dd>{guestsLabel(menu.min_guests, menu.max_guests)}</dd>
        {period && (<><dt>Период</dt><dd>{period}</dd></>)}
      </dl>

      <div className="menu-card__counts">
        <span className="menu-count-chip">{sectionCount} секц.</span>
        <span className="menu-count-chip">{itemCount} блюд</span>
        <span className="menu-count-chip">{extraCount} доп.</span>
      </div>

      {confirming ? (
        <div className="admin-card__confirm">
          <span>Удалить меню «{menu.name_ru}» со всеми секциями, позициями и опциями?</span>
          <div className="admin-card__confirm-actions">
            <button type="button" className="admin-table__link admin-table__link--danger" disabled={busy} onClick={onConfirmDelete}>
              {busy ? 'Удаляем…' : 'Да, удалить'}
            </button>
            <button type="button" className="admin-table__link" onClick={onCancelDelete}>Отмена</button>
          </div>
        </div>
      ) : (
        <div className="admin-card__actions">
          <button type="button" className="admin-table__link" onClick={onToggleBuilder}>
            {expanded ? 'Свернуть состав' : 'Состав меню'}
          </button>
          <button type="button" className="admin-table__link" onClick={onEdit}>Редактировать</button>
          <button type="button" className="admin-table__link" disabled={duplicating} onClick={onDuplicate}>
            {duplicating ? 'Копируем…' : 'Дублировать'}
          </button>
          <button type="button" className="admin-table__link" disabled={busy} onClick={onToggle}>
            {menu.is_active ? 'Скрыть' : 'Активировать'}
          </button>
          <button type="button" className="admin-table__link admin-table__link--danger" onClick={onAskDelete}>Удалить</button>
        </div>
      )}
    </div>
  );
}

function MenuForm({ mode, form, setForm, halls, onSave, onCancel, saving, error }) {
  function set(key, value) {
    setForm((f) => ({ ...f, [key]: value }));
  }
  const selectedHall = halls.find((h) => String(h.id) === String(form.hall_id));
  const dateError = Boolean(form.valid_from && form.valid_until && form.valid_until < form.valid_from);

  return (
    <form className="contacts__form admin-form-card" onSubmit={(e) => { e.preventDefault(); onSave(); }}>
      <div className="admin-form-card__head">
        <h3 className="admin-form-card__title">{mode === 'create' ? 'Новое меню' : 'Редактирование меню'}</h3>
      </div>

      <fieldset className="admin-fieldset">
        <legend className="admin-fieldset__legend">Основная информация</legend>
        <div className="form-row">
          <label>
            <span>Название на русском *</span>
            <input value={form.name_ru} onChange={(e) => set('name_ru', e.target.value)} placeholder="Например: Меню 25 000" required />
          </label>
          <label>
            <span>Название на казахском</span>
            <input value={form.name_kz} onChange={(e) => set('name_kz', e.target.value)} placeholder="Мысалы: 25 000 мәзірі" required />
          </label>
        </div>
        <div className="form-row">
          <label>
            <span>Описание на русском</span>
            <textarea rows="3" value={form.description_ru} onChange={(e) => set('description_ru', e.target.value)} placeholder="Что входит, для каких мероприятий…" />
          </label>
          <label>
            <span>Описание на казахском</span>
            <textarea rows="3" value={form.description_kz} onChange={(e) => set('description_kz', e.target.value)} placeholder="Не кіреді, қандай іс-шараларға…" />
          </label>
        </div>
      </fieldset>

      <fieldset className="admin-fieldset">
        <legend className="admin-fieldset__legend">Цена и гости</legend>
        <div className="form-row">
          <label>
            <span>Цена на одного гостя, ₸</span>
            <input type="number" min="0" inputMode="numeric" value={form.price_per_guest} onChange={(e) => set('price_per_guest', e.target.value)} placeholder="Например: 25 000" />
            <small className="admin-field-hint">Итоговая стоимость будет рассчитана как цена × количество гостей.</small>
          </label>
          <span aria-hidden="true" />
        </div>
        <div className="form-row">
          <label>
            <span>Минимум гостей</span>
            <input type="number" min="0" inputMode="numeric" value={form.min_guests} onChange={(e) => set('min_guests', e.target.value)} placeholder="Например: 50" />
            <small className="admin-field-hint">Пусто — без ограничения</small>
          </label>
          <label>
            <span>Максимум гостей</span>
            <input type="number" min="0" inputMode="numeric" value={form.max_guests} onChange={(e) => set('max_guests', e.target.value)} placeholder="Например: 250" />
            <small className="admin-field-hint">Пусто — без ограничения</small>
          </label>
        </div>
      </fieldset>

      <fieldset className="admin-fieldset">
        <legend className="admin-fieldset__legend">Зал</legend>
        <div className="form-row">
          <label>
            <span>Зал</span>
            <select value={form.hall_id} onChange={(e) => set('hall_id', e.target.value)}>
              <option value="">Любой зал</option>
              {halls.map((h) => (
                <option key={h.id} value={h.id}>
                  {h.name_ru}{h.capacity ? ` — до ${h.capacity} гостей` : ''}
                </option>
              ))}
            </select>
            <small className="admin-field-hint">
              {selectedHall
                ? 'Это меню будет доступно только для выбранного зала.'
                : 'Меню можно использовать в любом зале ресторана.'}
            </small>
          </label>
          <span aria-hidden="true" />
        </div>
      </fieldset>

      <fieldset className="admin-fieldset">
        <legend className="admin-fieldset__legend">Период действия</legend>
        <div className="form-row">
          <label>
            <span>Действует с</span>
            <input type="date" value={form.valid_from} onChange={(e) => set('valid_from', e.target.value)} />
          </label>
          <label>
            <span>Действует по</span>
            <input type="date" value={form.valid_until} onChange={(e) => set('valid_until', e.target.value)} />
          </label>
        </div>
        {dateError ? (
          <p className="admin-field-error">Дата «действует по» не может быть раньше даты «действует с».</p>
        ) : (
          <p className="admin-field-hint" style={{ marginTop: 0 }}>
            {!form.valid_from && !form.valid_until
              ? 'Без ограничения по дате'
              : 'Меню показывается клиентам только в этот период'}
          </p>
        )}
      </fieldset>

      <fieldset className="admin-fieldset">
        <legend className="admin-fieldset__legend">Порядок и статус</legend>
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
              <b>Активно</b>
              <small>Меню доступно клиентам</small>
            </span>
          </label>
        </div>
      </fieldset>

      {error && <p className="admin-banner admin-banner--error" style={{ marginBottom: 0 }}>{error}</p>}

      <div className="admin-form-card__actions">
        <button type="submit" className="btn btn--gold" disabled={saving || dateError}>
          {saving
            ? <><span className="admin-spinner" aria-hidden="true" /> Сохранение…</>
            : (mode === 'create' ? 'Сохранить меню' : 'Сохранить изменения')}
        </button>
        <button type="button" className="btn btn--outline" onClick={onCancel} disabled={saving}>Отмена</button>
      </div>
    </form>
  );
}
