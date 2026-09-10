'use client';

import { useState } from 'react';
import { adminApi } from '@/lib/adminApi';
import { pluralRu } from '@/lib/format';

// Lines with no leading "-"/"•" start a new section; "-"/"•"-prefixed
// lines are items under the most recent section (an item before any
// section header lands in an implicit "Без названия" one). An optional
// " — <текст>" suffix on an item line becomes its quantity_text.
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

const EXAMPLE = [
  'Холодные закуски',
  'Мясное ассорти',
  'Рыбное ассорти',
  '',
  'Салаты',
  'Салат с буратой',
  'Салат с копченой семгой',
  '',
  'Основное горячее',
  'Бешбармак',
].join('\n');

/** "Быстро создать меню из текста": textarea → распознать → preview →
 * явное подтверждение → только тогда что-либо пишется в backend. Логика
 * разбора и сохранения не менялась — только оформление. */
export default function RestaurantMenuImport({ listingId, menuId, existingSectionCount, onClose, onImported }) {
  const [text, setText] = useState('');
  const [preview, setPreview] = useState(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const itemTotal = preview ? preview.reduce((n, s) => n + s.items.length, 0) : 0;

  function handlePreview() {
    setPreview(parseMenuText(text));
    setError('');
  }

  async function handleConfirm() {
    setSaving(true);
    setError('');
    try {
      let sectionOrder = existingSectionCount;
      for (const section of preview) {
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
    <div className="menu-import">
      <div className="menu-import__head">
        <span className="menu-import__title">Быстро создать меню из текста</span>
        <button type="button" className="admin-table__link" onClick={onClose}>Закрыть</button>
      </div>

      {!preview && (
        <>
          <p className="admin-field-hint" style={{ margin: '0 0 8px' }}>
            Строка без «-» — новая секция, строки под ней — позиции. Пример:
          </p>
          <pre className="menu-import__example">{EXAMPLE}</pre>
          <textarea
            className="admin-import-textarea"
            value={text}
            onChange={(e) => setText(e.target.value)}
            placeholder={EXAMPLE}
          />
          <div className="menu-inline-form__actions" style={{ marginTop: 12 }}>
            <button type="button" className="btn btn--gold btn--sm" onClick={handlePreview} disabled={!text.trim()}>
              Распознать меню
            </button>
          </div>
        </>
      )}

      {preview && (
        <>
          <div className="menu-import__preview">
            {preview.length === 0 && <p className="admin-empty__text" style={{ textAlign: 'left', margin: 0 }}>Не удалось распознать ни одной секции</p>}
            {preview.map((section, i) => (
              <div className="menu-import__preview-section" key={i}>
                <strong>{section.title_ru}</strong>
                <ul>
                  {section.items.map((item, j) => (
                    <li key={j}>{item.name_ru}{item.quantity_text ? ` — ${item.quantity_text}` : ''}</li>
                  ))}
                </ul>
              </div>
            ))}
          </div>

          <p className="menu-import__counts">
            {preview.length} {pluralRu(preview.length, ['секция', 'секции', 'секций'])} ·{' '}
            {itemTotal} {pluralRu(itemTotal, ['позиция', 'позиции', 'позиций'])}.
            Названия на казахском заполнятся так же, как на русском — их можно поправить после.
          </p>

          {error && <p className="admin-banner admin-banner--error">{error}</p>}

          <div className="menu-inline-form__actions" style={{ marginTop: 12 }}>
            <button type="button" className="btn btn--gold btn--sm" onClick={handleConfirm} disabled={saving || preview.length === 0}>
              {saving ? 'Добавляем…' : 'Подтвердить и добавить'}
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
