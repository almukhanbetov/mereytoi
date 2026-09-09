'use client';

import { useState } from 'react';
import { adminApi } from '@/lib/adminApi';
import RestaurantMenuImport from './RestaurantMenuImport';

const EMPTY_SECTION = { title_ru: '', title_kz: '', sort_order: 0 };
const EMPTY_ITEM = { name_ru: '', name_kz: '', description_ru: '', description_kz: '', quantity_text: '', sort_order: 0 };

/** Brief section 4 — sections → items, inside one menu. Reordering is
 * ↑/↓ buttons (same reasoning as RestaurantHallsTab's own — reliable and
 * keyboard-accessible without needing to visually verify a drag
 * interaction in this environment). `refresh` re-fetches the whole
 * listing tree after every mutation (see adminApi.js's own doc comment
 * on why) rather than hand-patching this deeply nested local state. */
export default function RestaurantMenuSections({ listingId, menu, refresh }) {
  const sections = [...(menu.sections || [])].sort((a, b) => a.sort_order - b.sort_order);

  const [addingSection, setAddingSection] = useState(false);
  const [sectionForm, setSectionForm] = useState(EMPTY_SECTION);
  const [editingSectionId, setEditingSectionId] = useState(null);
  const [addingItemTo, setAddingItemTo] = useState(null);
  const [itemForm, setItemForm] = useState(EMPTY_ITEM);
  const [editingItem, setEditingItem] = useState(null); // { sectionId, itemId }
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [showImport, setShowImport] = useState(false);

  async function createSection() {
    setBusy(true);
    setError('');
    try {
      await adminApi.createSection(listingId, menu.id, { ...sectionForm, sort_order: sections.length });
      await refresh();
      setAddingSection(false);
      setSectionForm(EMPTY_SECTION);
    } catch (err) {
      setError(err.message || 'Не удалось создать секцию');
    } finally {
      setBusy(false);
    }
  }

  async function saveSection(sectionId) {
    setBusy(true);
    setError('');
    try {
      await adminApi.updateSection(listingId, menu.id, sectionId, sectionForm);
      await refresh();
      setEditingSectionId(null);
    } catch (err) {
      setError(err.message || 'Не удалось сохранить секцию');
    } finally {
      setBusy(false);
    }
  }

  async function removeSection(section) {
    if (!window.confirm(`Удалить секцию «${section.title_ru}» вместе со всеми позициями?`)) return;
    try {
      await adminApi.deleteSection(listingId, menu.id, section.id);
      await refresh();
    } catch (err) {
      alert(err.message || 'Не удалось удалить секцию');
    }
  }

  async function moveSection(section, direction) {
    const idx = sections.findIndex((s) => s.id === section.id);
    const swapIdx = idx + direction;
    if (swapIdx < 0 || swapIdx >= sections.length) return;
    const a = sections[idx];
    const b = sections[swapIdx];
    try {
      await Promise.all([
        adminApi.updateSection(listingId, menu.id, a.id, { title_ru: a.title_ru, title_kz: a.title_kz, sort_order: b.sort_order }),
        adminApi.updateSection(listingId, menu.id, b.id, { title_ru: b.title_ru, title_kz: b.title_kz, sort_order: a.sort_order }),
      ]);
      await refresh();
    } catch (err) {
      alert(err.message || 'Не удалось изменить порядок секций');
    }
  }

  async function createItem(sectionId) {
    setBusy(true);
    setError('');
    try {
      const section = sections.find((s) => s.id === sectionId);
      await adminApi.createItem(listingId, menu.id, sectionId, { ...itemForm, sort_order: (section.items || []).length });
      await refresh();
      setAddingItemTo(null);
      setItemForm(EMPTY_ITEM);
    } catch (err) {
      setError(err.message || 'Не удалось добавить позицию');
    } finally {
      setBusy(false);
    }
  }

  async function saveItem(sectionId, itemId) {
    setBusy(true);
    setError('');
    try {
      await adminApi.updateItem(listingId, menu.id, sectionId, itemId, itemForm);
      await refresh();
      setEditingItem(null);
    } catch (err) {
      setError(err.message || 'Не удалось сохранить позицию');
    } finally {
      setBusy(false);
    }
  }

  async function removeItem(sectionId, item) {
    if (!window.confirm(`Удалить «${item.name_ru}»?`)) return;
    try {
      await adminApi.deleteItem(listingId, menu.id, sectionId, item.id);
      await refresh();
    } catch (err) {
      alert(err.message || 'Не удалось удалить позицию');
    }
  }

  async function moveItem(section, item, direction) {
    const items = [...(section.items || [])].sort((a, b) => a.sort_order - b.sort_order);
    const idx = items.findIndex((i) => i.id === item.id);
    const swapIdx = idx + direction;
    if (swapIdx < 0 || swapIdx >= items.length) return;
    const a = items[idx];
    const b = items[swapIdx];
    try {
      await Promise.all([
        adminApi.updateItem(listingId, menu.id, section.id, a.id, { ...a, sort_order: b.sort_order }),
        adminApi.updateItem(listingId, menu.id, section.id, b.id, { ...b, sort_order: a.sort_order }),
      ]);
      await refresh();
    } catch (err) {
      alert(err.message || 'Не удалось изменить порядок позиций');
    }
  }

  return (
    <div>
      <div className="admin-section-block__head" style={{ border: 'none', marginBottom: 4, paddingBottom: 0 }}>
        <h4 style={{ margin: 0, fontSize: 14 }}>Секции и позиции</h4>
        <div style={{ display: 'flex', gap: 14 }}>
          <button type="button" className="admin-table__link" onClick={() => setShowImport((v) => !v)}>
            {showImport ? 'Скрыть импорт' : 'Вставить меню текстом'}
          </button>
          {!addingSection && (
            <button type="button" className="admin-table__link" onClick={() => { setSectionForm({ ...EMPTY_SECTION, sort_order: sections.length }); setAddingSection(true); }}>
              + Секция
            </button>
          )}
        </div>
      </div>

      {showImport && (
        <RestaurantMenuImport
          listingId={listingId}
          menuId={menu.id}
          existingSectionCount={sections.length}
          onClose={() => setShowImport(false)}
          onImported={async () => {
            setShowImport(false);
            await refresh();
          }}
        />
      )}

      {addingSection && (
        <div className="admin-section-block">
          <div className="form-row">
            <label>
              <span>Название секции (рус)</span>
              <input value={sectionForm.title_ru} onChange={(e) => setSectionForm((f) => ({ ...f, title_ru: e.target.value }))} />
            </label>
            <label>
              <span>Название секции (қаз)</span>
              <input value={sectionForm.title_kz} onChange={(e) => setSectionForm((f) => ({ ...f, title_kz: e.target.value }))} />
            </label>
          </div>
          {error && <p className="admin-login__error">{error}</p>}
          <div style={{ display: 'flex', gap: 10 }}>
            <button type="button" className="btn btn--gold btn--sm" disabled={busy} onClick={createSection}>Сохранить секцию</button>
            <button type="button" className="btn btn--outline btn--sm" onClick={() => setAddingSection(false)}>Отмена</button>
          </div>
        </div>
      )}

      {sections.length === 0 && !addingSection && <p className="admin-table__empty">Секций пока нет</p>}

      {sections.map((section, si) => {
        const items = [...(section.items || [])].sort((a, b) => a.sort_order - b.sort_order);
        return (
          <div className="admin-section-block" key={section.id}>
            {editingSectionId === section.id ? (
              <>
                <div className="form-row">
                  <label>
                    <span>Название (рус)</span>
                    <input value={sectionForm.title_ru} onChange={(e) => setSectionForm((f) => ({ ...f, title_ru: e.target.value }))} />
                  </label>
                  <label>
                    <span>Название (қаз)</span>
                    <input value={sectionForm.title_kz} onChange={(e) => setSectionForm((f) => ({ ...f, title_kz: e.target.value }))} />
                  </label>
                </div>
                {error && <p className="admin-login__error">{error}</p>}
                <div style={{ display: 'flex', gap: 10 }}>
                  <button type="button" className="btn btn--gold btn--sm" disabled={busy} onClick={() => saveSection(section.id)}>Сохранить</button>
                  <button type="button" className="btn btn--outline btn--sm" onClick={() => setEditingSectionId(null)}>Отмена</button>
                </div>
              </>
            ) : (
              <>
                <div className="admin-section-block__head">
                  <span className="admin-section-block__title">{section.title_ru}</span>
                  <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
                    <span className="admin-card__order">
                      <button type="button" className="admin-icon-btn" disabled={si === 0} onClick={() => moveSection(section, -1)} aria-label="Выше">↑</button>
                      <button type="button" className="admin-icon-btn" disabled={si === sections.length - 1} onClick={() => moveSection(section, 1)} aria-label="Ниже">↓</button>
                    </span>
                    <button
                      type="button"
                      className="admin-table__link"
                      onClick={() => { setSectionForm({ title_ru: section.title_ru, title_kz: section.title_kz, sort_order: section.sort_order }); setEditingSectionId(section.id); }}
                    >
                      Изменить
                    </button>
                    <button type="button" className="admin-table__link admin-table__link--danger" onClick={() => removeSection(section)}>Удалить</button>
                  </div>
                </div>

                <div className="admin-inline-list">
                  {items.length === 0 && <p className="admin-table__empty" style={{ padding: '8px 0' }}>Нет позиций</p>}
                  {items.map((item, ii) =>
                    editingItem?.sectionId === section.id && editingItem?.itemId === item.id ? (
                      <div className="admin-section-block" key={item.id} style={{ marginBottom: 0 }}>
                        <div className="form-row">
                          <label>
                            <span>Название (рус)</span>
                            <input value={itemForm.name_ru} onChange={(e) => setItemForm((f) => ({ ...f, name_ru: e.target.value }))} />
                          </label>
                          <label>
                            <span>Название (қаз)</span>
                            <input value={itemForm.name_kz} onChange={(e) => setItemForm((f) => ({ ...f, name_kz: e.target.value }))} />
                          </label>
                        </div>
                        <div className="form-row">
                          <label>
                            <span>Описание (рус)</span>
                            <input value={itemForm.description_ru} onChange={(e) => setItemForm((f) => ({ ...f, description_ru: e.target.value }))} />
                          </label>
                          <label>
                            <span>Кол-во/вес</span>
                            <input value={itemForm.quantity_text} onChange={(e) => setItemForm((f) => ({ ...f, quantity_text: e.target.value }))} placeholder="200 г" />
                          </label>
                        </div>
                        {error && <p className="admin-login__error">{error}</p>}
                        <div style={{ display: 'flex', gap: 10 }}>
                          <button type="button" className="btn btn--gold btn--sm" disabled={busy} onClick={() => saveItem(section.id, item.id)}>Сохранить</button>
                          <button type="button" className="btn btn--outline btn--sm" onClick={() => setEditingItem(null)}>Отмена</button>
                        </div>
                      </div>
                    ) : (
                      <div className="admin-inline-row" key={item.id}>
                        <span>{item.name_ru}{item.quantity_text ? ` — ${item.quantity_text}` : ''}</span>
                        <span className="admin-inline-row__actions">
                          <button type="button" className="admin-icon-btn" disabled={ii === 0} onClick={() => moveItem(section, item, -1)} aria-label="Выше">↑</button>
                          <button type="button" className="admin-icon-btn" disabled={ii === items.length - 1} onClick={() => moveItem(section, item, 1)} aria-label="Ниже">↓</button>
                          <button
                            type="button"
                            className="admin-table__link"
                            onClick={() => {
                              setItemForm({
                                name_ru: item.name_ru, name_kz: item.name_kz,
                                description_ru: item.description_ru || '', description_kz: item.description_kz || '',
                                quantity_text: item.quantity_text || '', sort_order: item.sort_order,
                              });
                              setEditingItem({ sectionId: section.id, itemId: item.id });
                            }}
                          >
                            Изменить
                          </button>
                          <button type="button" className="admin-table__link admin-table__link--danger" onClick={() => removeItem(section.id, item)}>Удалить</button>
                        </span>
                      </div>
                    )
                  )}
                </div>

                {addingItemTo === section.id ? (
                  <div className="admin-section-block" style={{ marginBottom: 0 }}>
                    <div className="form-row">
                      <label>
                        <span>Название (рус)</span>
                        <input value={itemForm.name_ru} onChange={(e) => setItemForm((f) => ({ ...f, name_ru: e.target.value }))} />
                      </label>
                      <label>
                        <span>Название (қаз)</span>
                        <input value={itemForm.name_kz} onChange={(e) => setItemForm((f) => ({ ...f, name_kz: e.target.value }))} />
                      </label>
                    </div>
                    <label>
                      <span>Кол-во/вес</span>
                      <input value={itemForm.quantity_text} onChange={(e) => setItemForm((f) => ({ ...f, quantity_text: e.target.value }))} placeholder="200 г" />
                    </label>
                    {error && <p className="admin-login__error">{error}</p>}
                    <div style={{ display: 'flex', gap: 10 }}>
                      <button type="button" className="btn btn--gold btn--sm" disabled={busy} onClick={() => createItem(section.id)}>Добавить позицию</button>
                      <button type="button" className="btn btn--outline btn--sm" onClick={() => setAddingItemTo(null)}>Отмена</button>
                    </div>
                  </div>
                ) : (
                  <button type="button" className="admin-table__link" onClick={() => { setItemForm(EMPTY_ITEM); setAddingItemTo(section.id); }}>+ Позиция</button>
                )}
              </>
            )}
          </div>
        );
      })}
    </div>
  );
}
