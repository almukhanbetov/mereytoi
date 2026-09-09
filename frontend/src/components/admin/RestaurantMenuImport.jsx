'use client';

import { useState } from 'react';
import { adminApi } from '@/lib/adminApi';

// Lines with no leading "-"/"•" start a new section; "-"/"•"-prefixed
// lines are items under the most recent section (an item before any
// section header lands in an implicit "Без названия" one, rather than
// being silently dropped). An optional " — <текст>" suffix on an item
// line becomes its quantity_text — matches the brief's own example
// ("Мясное ассорти" with no suffix is just a name; "200 г" style notes
// are opt-in, not required).
function parseMenuText(text) {
  const lines = text.split('\n').map((l) => l.trim()).filter((l) => l.length > 0);
  const sections = [];
  let current = null;
  for (const line of lines) {
    const isItem = /^[-•]\s*/.test(line);
    if (isItem) {
      if (!current) {
        current = { title_ru: 'Без названия', items: [] };
        sections.push(current);
      }
      let rest = line.replace(/^[-•]\s*/, '');
      let quantityText = '';
      const dashSplit = rest.split(/\s+—\s+/);
      if (dashSplit.length > 1) {
        rest = dashSplit[0];
        quantityText = dashSplit.slice(1).join(' — ');
      }
      current.items.push({ name_ru: rest, quantity_text: quantityText });
    } else {
      current = { title_ru: line, items: [] };
      sections.push(current);
    }
  }
  return sections;
}

/** Brief section 6 — "Вставить меню текстом": textarea → parse preview →
 * explicit confirm → only then does anything get saved. Nothing is
 * written to the backend until "Подтвердить и сохранить" is clicked. */
export default function RestaurantMenuImport({ listingId, menuId, existingSectionCount, onClose, onImported }) {
  const [text, setText] = useState('');
  const [preview, setPreview] = useState(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  function handlePreview() {
    setPreview(parseMenuText(text));
  }

  async function handleConfirm() {
    setSaving(true);
    setError('');
    try {
      let sectionOrder = existingSectionCount;
      for (const section of preview) {
        // Kazakh names default to the Russian text — a bulk paste is
        // Russian-only input; nothing here fabricates a translation, the
        // admin can correct name_kz afterward via the normal per-item edit
        // form (RestaurantMenuSections), same as every other field here.
        const { section: created } = await adminApi.createSection(listingId, menuId, {
          title_ru: section.title_ru,
          title_kz: section.title_ru,
          sort_order: sectionOrder++,
        });
        let itemOrder = 0;
        for (const item of section.items) {
          await adminApi.createItem(listingId, menuId, created.id, {
            name_ru: item.name_ru,
            name_kz: item.name_ru,
            quantity_text: item.quantity_text,
            sort_order: itemOrder++,
          });
        }
      }
      onImported();
    } catch (err) {
      setError(err.message || 'Не удалось импортировать меню');
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="admin-section-block">
      <div className="admin-section-block__head">
        <span className="admin-section-block__title">Вставить меню текстом</span>
        <button type="button" className="admin-table__link" onClick={onClose}>Закрыть</button>
      </div>

      {!preview && (
        <>
          <p className="booking-workspace-cta__text" style={{ marginTop: 0 }}>
            Строка без «-» — новая секция, строки с «-» — позиции внутри неё. Пример:
          </p>
          <pre style={{ fontSize: 12.5, background: 'var(--surface-tint)', padding: '10px 14px', borderRadius: 8, margin: '0 0 12px' }}>
            {'Холодные закуски\n- Мясное ассорти\n- Рыбное ассорти\n\nСалаты\n- Салат с буратой'}
          </pre>
          <textarea
            className="admin-import-textarea"
            value={text}
            onChange={(e) => setText(e.target.value)}
            placeholder={'Холодные закуски\n- Мясное ассорти\n- Рыбное ассорти'}
          />
          <div style={{ display: 'flex', gap: 10, marginTop: 12 }}>
            <button type="button" className="btn btn--outline btn--sm" onClick={handlePreview} disabled={!text.trim()}>
              Предпросмотр
            </button>
          </div>
        </>
      )}

      {preview && (
        <>
          <div className="admin-import-preview">
            {preview.length === 0 && <p className="admin-table__empty">Не удалось распознать ни одной секции</p>}
            {preview.map((section, i) => (
              <div key={i} style={{ marginBottom: 12 }}>
                <strong>{section.title_ru}</strong>
                <ul style={{ margin: '6px 0 0', paddingLeft: 20 }}>
                  {section.items.map((item, j) => (
                    <li key={j}>{item.name_ru}{item.quantity_text ? ` — ${item.quantity_text}` : ''}</li>
                  ))}
                </ul>
              </div>
            ))}
          </div>
          <p className="booking-workspace-cta__text booking-workspace-cta__text--muted">
            Названия на казахском заполнятся так же, как на русском — их можно поправить после сохранения.
          </p>
          {error && <p className="admin-login__error">{error}</p>}
          <div style={{ display: 'flex', gap: 10, marginTop: 12 }}>
            <button type="button" className="btn btn--gold btn--sm" onClick={handleConfirm} disabled={saving || preview.length === 0}>
              {saving ? 'Сохраняем…' : 'Подтвердить и сохранить'}
            </button>
            <button type="button" className="btn btn--outline btn--sm" onClick={() => setPreview(null)} disabled={saving}>
              Назад к тексту
            </button>
          </div>
        </>
      )}
    </div>
  );
}
