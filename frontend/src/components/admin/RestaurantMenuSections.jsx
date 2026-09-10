'use client';

import { useState } from 'react';
import { adminApi } from '@/lib/adminApi';
import { pluralRu } from '@/lib/format';
import RestaurantMenuImport from './RestaurantMenuImport';

const EMPTY_SECTION = { title_ru: '', title_kz: '', sort_order: 0 };
const EMPTY_ITEM = { name_ru: '', name_kz: '', description_ru: '', description_kz: '', quantity_text: '', sort_order: 0 };

/** Sections → items inside one menu. Frontend-only restyle of the existing
 * builder — every adminApi call, payload and the models behind them are
 * unchanged. Reorder is ↑/↓ (reliable + keyboard-accessible). `refresh`
 * re-fetches the whole listing tree after each mutation (see adminApi.js's
 * own doc comment) rather than hand-patching this deeply nested state. */
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
  const [confirmSectionId, setConfirmSectionId] = useState(null);
  const [confirmItem, setConfirmItem] = useState(null); // { sectionId, itemId }

  async function createSection() {
    if (!sectionForm.title_ru.trim() || !sectionForm.title_kz.trim()) {
      setError('Укажите название секции на русском и казахском');
      return;
    }
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
    if (!sectionForm.title_ru.trim() || !sectionForm.title_kz.trim()) {
      setError('Укажите название секции на русском и казахском');
      return;
    }
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
    setBusy(true);
    setError('');
    try {
      await adminApi.deleteSection(listingId, menu.id, section.id);
      await refresh();
      setConfirmSectionId(null);
    } catch (err) {
      setError(err.message || 'Не удалось удалить секцию');
    } finally {
      setBusy(false);
    }
  }

  async function moveSection(section, direction) {
    const idx = sections.findIndex((s) => s.id === section.id);
    const swapIdx = idx + direction;
    if (swapIdx < 0 || swapIdx >= sections.length) return;
    const a = sections[idx];
    const b = sections[swapIdx];
    setError('');
    try {
      await Promise.all([
        adminApi.updateSection(listingId, menu.id, a.id, { title_ru: a.title_ru, title_kz: a.title_kz, sort_order: b.sort_order }),
        adminApi.updateSection(listingId, menu.id, b.id, { title_ru: b.title_ru, title_kz: b.title_kz, sort_order: a.sort_order }),
      ]);
      await refresh();
    } catch (err) {
      setError(err.message || 'Не удалось изменить порядок секций');
    }
  }

  async function createItem(sectionId) {
    if (!itemForm.name_ru.trim() || !itemForm.name_kz.trim()) {
      setError('Укажите название позиции на русском и казахском');
      return;
    }
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
    if (!itemForm.name_ru.trim() || !itemForm.name_kz.trim()) {
      setError('Укажите название позиции на русском и казахском');
      return;
    }
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
    setBusy(true);
    setError('');
    try {
      await adminApi.deleteItem(listingId, menu.id, sectionId, item.id);
      await refresh();
      setConfirmItem(null);
    } catch (err) {
      setError(err.message || 'Не удалось удалить позицию');
    } finally {
      setBusy(false);
    }
  }

  async function moveItem(section, item, direction) {
    const items = [...(section.items || [])].sort((a, b) => a.sort_order - b.sort_order);
    const idx = items.findIndex((i) => i.id === item.id);
    const swapIdx = idx + direction;
    if (swapIdx < 0 || swapIdx >= items.length) return;
    const a = items[idx];
    const b = items[swapIdx];
    setError('');
    try {
      await Promise.all([
        adminApi.updateItem(listingId, menu.id, section.id, a.id, { ...a, sort_order: b.sort_order }),
        adminApi.updateItem(listingId, menu.id, section.id, b.id, { ...b, sort_order: a.sort_order }),
      ]);
      await refresh();
    } catch (err) {
      setError(err.message || 'Не удалось изменить порядок позиций');
    }
  }

  function startEditSection(section) {
    setSectionForm({ title_ru: section.title_ru, title_kz: section.title_kz, sort_order: section.sort_order });
    setEditingSectionId(section.id);
    setError('');
  }
  function startEditItem(section, item) {
    setItemForm({
      name_ru: item.name_ru, name_kz: item.name_kz,
      description_ru: item.description_ru || '', description_kz: item.description_kz || '',
      quantity_text: item.quantity_text || '', sort_order: item.sort_order,
    });
    setEditingItem({ sectionId: section.id, itemId: item.id });
    setError('');
  }

  return (
    <div>
      <div className="menu-builder__block-head">
        <span className="menu-builder__block-title">Секции меню</span>
        <div className="menu-builder__block-actions">
          <button type="button" className="admin-table__link" onClick={() => setShowImport((v) => !v)}>
            {showImport ? 'Скрыть импорт' : 'Вставить меню текстом'}
          </button>
          {!addingSection && (
            <button
              type="button"
              className="admin-table__link"
              onClick={() => { setSectionForm({ ...EMPTY_SECTION, sort_order: sections.length }); setAddingSection(true); setError(''); }}
            >
              + Добавить секцию
            </button>
          )}
        </div>
      </div>

      {error && <p className="admin-banner admin-banner--error">{error}</p>}

      {showImport && (
        <RestaurantMenuImport
          listingId={listingId}
          menuId={menu.id}
          existingSectionCount={sections.length}
          onClose={() => setShowImport(false)}
          onImported={async () => { setShowImport(false); await refresh(); }}
        />
      )}

      {addingSection && (
        <SectionForm
          values={sectionForm}
          setValues={setSectionForm}
          onSave={createSection}
          onCancel={() => { setAddingSection(false); setError(''); }}
          busy={busy}
          submitLabel="Добавить секцию"
        />
      )}

      {sections.length === 0 && !addingSection && (
        <p className="admin-empty__text" style={{ textAlign: 'left', margin: '4px 0' }}>
          Секций пока нет — добавьте первую или вставьте меню текстом.
        </p>
      )}

      {sections.map((section, si) => {
        const items = [...(section.items || [])].sort((a, b) => a.sort_order - b.sort_order);
        const isEditingSection = editingSectionId === section.id;
        return (
          <div className="menu-section" key={section.id}>
            {isEditingSection ? (
              <SectionForm
                values={sectionForm}
                setValues={setSectionForm}
                onSave={() => saveSection(section.id)}
                onCancel={() => { setEditingSectionId(null); setError(''); }}
                busy={busy}
                submitLabel="Сохранить"
              />
            ) : (
              <>
                <div className="menu-section__head">
                  <div>
                    <h4 className="menu-section__title">{section.title_ru}</h4>
                    {section.title_kz && section.title_kz !== section.title_ru && (
                      <p className="menu-section__sub">{section.title_kz}</p>
                    )}
                    <p className="menu-section__sub">
                      {items.length} {pluralRu(items.length, ['позиция', 'позиции', 'позиций'])}
                    </p>
                  </div>
                  <div className="menu-section__actions">
                    <span className="admin-card__order">
                      <button type="button" className="admin-icon-btn admin-icon-btn--sm" disabled={si === 0} onClick={() => moveSection(section, -1)} aria-label="Секцию выше">↑</button>
                      <button type="button" className="admin-icon-btn admin-icon-btn--sm" disabled={si === sections.length - 1} onClick={() => moveSection(section, 1)} aria-label="Секцию ниже">↓</button>
                    </span>
                    <button type="button" className="admin-table__link" onClick={() => startEditSection(section)}>Изменить</button>
                    {confirmSectionId === section.id ? (
                      <>
                        <button type="button" className="admin-table__link admin-table__link--danger" disabled={busy} onClick={() => removeSection(section)}>
                          {busy ? 'Удаляем…' : 'Точно удалить'}
                        </button>
                        <button type="button" className="admin-table__link" onClick={() => setConfirmSectionId(null)}>Отмена</button>
                      </>
                    ) : (
                      <button type="button" className="admin-table__link admin-table__link--danger" onClick={() => setConfirmSectionId(section.id)}>Удалить</button>
                    )}
                  </div>
                </div>

                <div className="menu-item-list">
                  {items.length === 0 && (
                    <p className="menu-item-row__sub" style={{ padding: '2px' }}>В этой секции пока нет позиций</p>
                  )}
                  {items.map((item, ii) =>
                    editingItem?.sectionId === section.id && editingItem?.itemId === item.id ? (
                      <ItemForm
                        key={item.id}
                        values={itemForm}
                        setValues={setItemForm}
                        onSave={() => saveItem(section.id, item.id)}
                        onCancel={() => { setEditingItem(null); setError(''); }}
                        busy={busy}
                        submitLabel="Сохранить"
                      />
                    ) : (
                      <div className="menu-item-row" key={item.id}>
                        <div className="menu-item-row__main">
                          <div className="menu-item-row__name">
                            {item.name_ru}{item.quantity_text ? ` · ${item.quantity_text}` : ''}
                          </div>
                          {item.name_kz && item.name_kz !== item.name_ru && (
                            <div className="menu-item-row__sub">{item.name_kz}</div>
                          )}
                          {item.description_ru && <div className="menu-item-row__sub">{item.description_ru}</div>}
                        </div>
                        <span className="menu-item-row__actions">
                          <button type="button" className="admin-icon-btn admin-icon-btn--sm" disabled={ii === 0} onClick={() => moveItem(section, item, -1)} aria-label="Позицию выше">↑</button>
                          <button type="button" className="admin-icon-btn admin-icon-btn--sm" disabled={ii === items.length - 1} onClick={() => moveItem(section, item, 1)} aria-label="Позицию ниже">↓</button>
                          <button type="button" className="admin-table__link" onClick={() => startEditItem(section, item)}>Изменить</button>
                          {confirmItem?.sectionId === section.id && confirmItem?.itemId === item.id ? (
                            <>
                              <button type="button" className="admin-table__link admin-table__link--danger" disabled={busy} onClick={() => removeItem(section.id, item)}>
                                {busy ? '…' : 'Точно'}
                              </button>
                              <button type="button" className="admin-table__link" onClick={() => setConfirmItem(null)}>Отмена</button>
                            </>
                          ) : (
                            <button type="button" className="admin-table__link admin-table__link--danger" onClick={() => setConfirmItem({ sectionId: section.id, itemId: item.id })}>Удалить</button>
                          )}
                        </span>
                      </div>
                    )
                  )}
                </div>

                {addingItemTo === section.id ? (
                  <ItemForm
                    values={itemForm}
                    setValues={setItemForm}
                    onSave={() => createItem(section.id)}
                    onCancel={() => { setAddingItemTo(null); setError(''); }}
                    busy={busy}
                    submitLabel="Добавить позицию"
                  />
                ) : (
                  <button
                    type="button"
                    className="menu-add-btn menu-add-btn--block"
                    onClick={() => { setItemForm(EMPTY_ITEM); setAddingItemTo(section.id); setError(''); }}
                  >
                    + Добавить позицию
                  </button>
                )}
              </>
            )}
          </div>
        );
      })}
    </div>
  );
}

function SectionForm({ values, setValues, onSave, onCancel, busy, submitLabel }) {
  function set(key, value) {
    setValues((f) => ({ ...f, [key]: value }));
  }
  return (
    <div className="menu-inline-form">
      <div className="form-row">
        <label>
          <span>Название секции на русском *</span>
          <input value={values.title_ru} onChange={(e) => set('title_ru', e.target.value)} placeholder="Например: Холодные закуски" />
        </label>
        <label>
          <span>Название секции на казахском</span>
          <input value={values.title_kz} onChange={(e) => set('title_kz', e.target.value)} placeholder="Мысалы: Салқын тағамдар" />
        </label>
      </div>
      <div className="menu-inline-form__actions">
        <button type="button" className="btn btn--gold btn--sm" disabled={busy} onClick={onSave}>
          {busy ? 'Сохранение…' : submitLabel}
        </button>
        <button type="button" className="btn btn--outline btn--sm" onClick={onCancel} disabled={busy}>Отмена</button>
      </div>
    </div>
  );
}

function ItemForm({ values, setValues, onSave, onCancel, busy, submitLabel }) {
  function set(key, value) {
    setValues((f) => ({ ...f, [key]: value }));
  }
  return (
    <div className="menu-inline-form">
      <div className="form-row">
        <label>
          <span>Название на русском *</span>
          <input value={values.name_ru} onChange={(e) => set('name_ru', e.target.value)} placeholder="Например: Мясное ассорти" />
        </label>
        <label>
          <span>Название на казахском</span>
          <input value={values.name_kz} onChange={(e) => set('name_kz', e.target.value)} placeholder="Мысалы: Ет ассортиси" />
        </label>
      </div>
      <div className="form-row">
        <label>
          <span>Описание на русском</span>
          <input value={values.description_ru} onChange={(e) => set('description_ru', e.target.value)} placeholder="Состав, подача…" />
        </label>
        <label>
          <span>Количество / вес</span>
          <input value={values.quantity_text} onChange={(e) => set('quantity_text', e.target.value)} placeholder="Например: 200 г" />
        </label>
      </div>
      <div className="menu-inline-form__actions">
        <button type="button" className="btn btn--gold btn--sm" disabled={busy} onClick={onSave}>
          {busy ? 'Сохранение…' : submitLabel}
        </button>
        <button type="button" className="btn btn--outline btn--sm" onClick={onCancel} disabled={busy}>Отмена</button>
      </div>
    </div>
  );
}
