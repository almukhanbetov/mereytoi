'use client';

import { useState } from 'react';
import { adminApi } from '@/lib/adminApi';
import { formatPrice } from '@/lib/format';
import RestaurantMenuSections from './RestaurantMenuSections';
import RestaurantMenuExtras from './RestaurantMenuExtras';

const EMPTY_MENU = {
  hall_id: '', name_ru: '', name_kz: '', description_ru: '', description_kz: '',
  price_per_guest: 0, min_guests: '', max_guests: '', is_active: true, sort_order: 0,
  valid_from: '', valid_until: '',
};

function sortByOrder(list) {
  return [...list].sort((a, b) => a.sort_order - b.sort_order);
}

function menuFormFromValues(f) {
  return {
    hall_id: f.hall_id === '' ? null : Number(f.hall_id),
    name_ru: f.name_ru,
    name_kz: f.name_kz,
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

// Same-shape payload built straight from an existing menu row — used by
// toggleActive/move, which change exactly one field and must resend the
// rest unchanged (ListingMenuHandler.UpdateMenu replaces the whole row,
// same non-PATCH contract ServiceForm's own submit already works around).
function menuUpdatePayloadFromRow(m) {
  return {
    hall_id: m.hall_id, name_ru: m.name_ru, name_kz: m.name_kz,
    description_ru: m.description_ru, description_kz: m.description_kz,
    price_per_guest: m.price_per_guest, min_guests: m.min_guests, max_guests: m.max_guests,
    is_active: m.is_active, sort_order: m.sort_order,
    valid_from: m.valid_from, valid_until: m.valid_until,
  };
}

/** Brief section 3 — menus list (accordion), create/edit/deactivate,
 * assign hall, price_per_guest, min/max guests, valid_from/until,
 * sort_order, and "Дублировать меню". Sections/items/extras (sections 4/5)
 * live inside each menu's expanded accordion body.
 *
 * `menus`/`halls`/`refresh` all come from the parent tab shell
 * (RestaurantAdminTabs) — not owned locally — so switching to the "Залы"
 * tab and back never leaves this showing a stale snapshot from before
 * this component last mounted. */
export default function RestaurantMenusTab({ listingId, menus: rawMenus, halls, refresh }) {
  const menus = sortByOrder(rawMenus);
  const [openId, setOpenId] = useState(null);
  const [creating, setCreating] = useState(false);
  const [editingId, setEditingId] = useState(null);
  const [form, setForm] = useState(EMPTY_MENU);
  const [saving, setSaving] = useState(false);
  const [duplicatingId, setDuplicatingId] = useState(null);
  const [error, setError] = useState('');

  function toggleOpen(id) {
    setOpenId((prev) => (prev === id ? null : id));
    setEditingId(null);
  }

  function startCreate() {
    setForm({ ...EMPTY_MENU, sort_order: menus.length });
    setCreating(true);
    setError('');
  }
  function startEdit(menu) {
    setForm({
      hall_id: menu.hall_id ?? '', name_ru: menu.name_ru, name_kz: menu.name_kz,
      description_ru: menu.description_ru || '', description_kz: menu.description_kz || '',
      price_per_guest: menu.price_per_guest, min_guests: menu.min_guests ?? '', max_guests: menu.max_guests ?? '',
      is_active: menu.is_active, sort_order: menu.sort_order,
      valid_from: menu.valid_from ? menu.valid_from.slice(0, 10) : '',
      valid_until: menu.valid_until ? menu.valid_until.slice(0, 10) : '',
    });
    setEditingId(menu.id);
    setOpenId(menu.id);
    setError('');
  }

  async function save() {
    setSaving(true);
    setError('');
    try {
      if (creating) await adminApi.createMenu(listingId, menuFormFromValues(form));
      else await adminApi.updateMenu(listingId, editingId, menuFormFromValues(form));
      await refresh();
      setCreating(false);
      setEditingId(null);
    } catch (err) {
      setError(err.message || 'Не удалось сохранить меню');
    } finally {
      setSaving(false);
    }
  }

  async function toggleActive(menu) {
    try {
      await adminApi.updateMenu(listingId, menu.id, { ...menuUpdatePayloadFromRow(menu), is_active: !menu.is_active });
      await refresh();
    } catch (err) {
      alert(err.message || 'Не удалось изменить статус меню');
    }
  }

  async function remove(menu) {
    if (!window.confirm(`Удалить меню «${menu.name_ru}» вместе со всеми секциями и позициями?`)) return;
    try {
      await adminApi.deleteMenu(listingId, menu.id);
      await refresh();
      if (openId === menu.id) setOpenId(null);
    } catch (err) {
      alert(err.message || 'Не удалось удалить меню');
    }
  }

  async function move(menu, direction) {
    const idx = menus.findIndex((m) => m.id === menu.id);
    const swapIdx = idx + direction;
    if (swapIdx < 0 || swapIdx >= menus.length) return;
    const a = menus[idx];
    const b = menus[swapIdx];
    try {
      await Promise.all([
        adminApi.updateMenu(listingId, a.id, { ...menuUpdatePayloadFromRow(a), sort_order: b.sort_order }),
        adminApi.updateMenu(listingId, b.id, { ...menuUpdatePayloadFromRow(b), sort_order: a.sort_order }),
      ]);
      await refresh();
    } catch (err) {
      alert(err.message || 'Не удалось изменить порядок меню');
    }
  }

  // Duplicate menu (brief section 3). No dedicated backend clone endpoint
  // exists — this stage is UI-only ("Backend/API уже готовы") — so this
  // composes the existing CRUD primitives client-side: create a new
  // inactive menu, then recreate each section/item/extra from the
  // already-loaded tree under it, in the same order.
  async function duplicate(menu) {
    setDuplicatingId(menu.id);
    setError('');
    try {
      const { menu: created } = await adminApi.createMenu(listingId, {
        hall_id: menu.hall_id ?? null,
        name_ru: menu.name_ru + ' (копия)',
        name_kz: menu.name_kz + ' (көшірме)',
        description_ru: menu.description_ru, description_kz: menu.description_kz,
        price_per_guest: menu.price_per_guest, min_guests: menu.min_guests, max_guests: menu.max_guests,
        is_active: false, sort_order: menus.length,
        valid_from: menu.valid_from, valid_until: menu.valid_until,
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
            description_ru: item.description_ru, description_kz: item.description_kz,
            quantity_text: item.quantity_text, sort_order: item.sort_order,
          });
        }
      }

      const sortedExtras = [...(menu.extras || [])].sort((a, b) => a.sort_order - b.sort_order);
      for (const extra of sortedExtras) {
        await adminApi.createExtra(listingId, created.id, {
          type: extra.type, title_ru: extra.title_ru, title_kz: extra.title_kz,
          price: extra.price, unit: extra.unit,
          description_ru: extra.description_ru, description_kz: extra.description_kz, sort_order: extra.sort_order,
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
    <div>
      <div className="admin-page-head" style={{ marginBottom: 18 }}>
        <h2 className="admin-section-title" style={{ margin: 0 }}>Меню</h2>
        {!creating && <button type="button" className="btn btn--gold btn--sm" onClick={startCreate}>+ Добавить меню</button>}
      </div>

      {error && <p className="admin-login__error">{error}</p>}

      {creating && (
        <div className="admin-accordion-item is-open" style={{ marginBottom: 14 }}>
          <div className="admin-accordion-body" style={{ paddingTop: 18 }}>
            <MenuForm form={form} setForm={setForm} halls={halls} onSave={save} onCancel={() => setCreating(false)} saving={saving} />
          </div>
        </div>
      )}

      {menus.length === 0 && !creating && <p className="admin-table__empty">Меню ещё не добавлены</p>}

      <div className="admin-accordion">
        {menus.map((menu, i) => {
          const isOpen = openId === menu.id;
          const hall = halls.find((h) => h.id === menu.hall_id);
          return (
            <div className={`admin-accordion-item${isOpen ? ' is-open' : ''}${menu.is_active ? '' : ' admin-accordion-item--inactive'}`} key={menu.id}>
              <div className="admin-accordion-head">
                <button type="button" className="admin-accordion-head__toggle" onClick={() => toggleOpen(menu.id)}>
                  <span className="admin-accordion-head__title">
                    {menu.name_ru}
                    <small>
                      {formatPrice(menu.price_per_guest)} / гость
                      {hall ? ` · ${hall.name_ru}` : ''}
                      {!menu.is_active ? ' · выключено' : ''}
                    </small>
                  </span>
                  <span className="admin-accordion-head__chevron">›</span>
                </button>
                <div className="admin-card__actions" style={{ margin: 0 }}>
                  <span className="admin-card__order">
                    <button type="button" className="admin-icon-btn" disabled={i === 0} onClick={() => move(menu, -1)} aria-label="Выше">↑</button>
                    <button type="button" className="admin-icon-btn" disabled={i === menus.length - 1} onClick={() => move(menu, 1)} aria-label="Ниже">↓</button>
                  </span>
                  <button type="button" className="admin-table__link" onClick={() => startEdit(menu)}>Изменить</button>
                  <button type="button" className="admin-table__link" disabled={duplicatingId === menu.id} onClick={() => duplicate(menu)}>
                    {duplicatingId === menu.id ? 'Дублируем…' : 'Дублировать меню'}
                  </button>
                  <button type="button" className="admin-table__link" onClick={() => toggleActive(menu)}>
                    {menu.is_active ? 'Деактивировать' : 'Активировать'}
                  </button>
                  <button type="button" className="admin-table__link admin-table__link--danger" onClick={() => remove(menu)}>Удалить</button>
                </div>
              </div>

              {isOpen && (
                <div className="admin-accordion-body">
                  {editingId === menu.id ? (
                    <MenuForm form={form} setForm={setForm} halls={halls} onSave={save} onCancel={() => setEditingId(null)} saving={saving} />
                  ) : (
                    <>
                      <RestaurantMenuSections listingId={listingId} menu={menu} refresh={refresh} />
                      <RestaurantMenuExtras listingId={listingId} menu={menu} refresh={refresh} />
                    </>
                  )}
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}

function MenuForm({ form, setForm, halls, onSave, onCancel, saving }) {
  function set(key, value) {
    setForm((f) => ({ ...f, [key]: value }));
  }
  return (
    <div>
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
          <span>Зал (необязательно)</span>
          <select value={form.hall_id} onChange={(e) => set('hall_id', e.target.value)}>
            <option value="">Любой зал</option>
            {halls.map((h) => (
              <option key={h.id} value={h.id}>{h.name_ru}</option>
            ))}
          </select>
        </label>
        <label>
          <span>Цена за гостя, ₸</span>
          <input type="number" min="0" value={form.price_per_guest} onChange={(e) => set('price_per_guest', e.target.value)} />
        </label>
      </div>
      <div className="form-row">
        <label>
          <span>Мин. гостей</span>
          <input type="number" min="0" value={form.min_guests} onChange={(e) => set('min_guests', e.target.value)} placeholder="без ограничения" />
        </label>
        <label>
          <span>Макс. гостей</span>
          <input type="number" min="0" value={form.max_guests} onChange={(e) => set('max_guests', e.target.value)} placeholder="без ограничения" />
        </label>
      </div>
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
          <span>Порядок сортировки</span>
          <input type="number" value={form.sort_order} onChange={(e) => set('sort_order', e.target.value)} />
        </label>
        <label style={{ flexDirection: 'row', alignItems: 'center', gap: 8, justifyContent: 'flex-start', paddingTop: 22 }}>
          <input type="checkbox" checked={form.is_active} onChange={(e) => set('is_active', e.target.checked)} style={{ width: 'auto' }} />
          <span style={{ fontWeight: 400, color: 'var(--text)' }}>Активно</span>
        </label>
      </div>
      <div style={{ display: 'flex', gap: 10 }}>
        <button type="button" className="btn btn--gold btn--sm" disabled={saving} onClick={onSave}>{saving ? 'Сохраняем…' : 'Сохранить меню'}</button>
        <button type="button" className="btn btn--outline btn--sm" onClick={onCancel}>Отмена</button>
      </div>
    </div>
  );
}
