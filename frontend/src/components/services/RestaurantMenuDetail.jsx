'use client';

import { useState } from 'react';
import { T } from '@/context/AppProviders';
import { formatPrice } from '@/lib/format';
import RestaurantMenuCalculator from './RestaurantMenuCalculator';

function formatDate(iso) {
  if (!iso) return null;
  return new Date(iso).toLocaleDateString('ru-RU', { day: '2-digit', month: 'long', year: 'numeric' });
}

/** Brief section 3 — one menu's detail: header facts, sections accordion
 * (multiple sections can be open at once — "Развернуть всё" only makes
 * sense that way), then Extras + Calculator (brief sections 4/5, combined
 * — see RestaurantMenuCalculator's own doc comment on why). */
export default function RestaurantMenuDetail({ menu, hall, listing }) {
  const sections = [...(menu.sections || [])].sort((a, b) => a.sort_order - b.sort_order);
  const [openIds, setOpenIds] = useState(() => new Set(sections.length <= 2 ? sections.map((s) => s.id) : []));

  function toggle(id) {
    setOpenIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }
  function expandAll() {
    setOpenIds(new Set(sections.map((s) => s.id)));
  }
  function collapseAll() {
    setOpenIds(new Set());
  }

  const validFrom = formatDate(menu.valid_from);
  const validUntil = formatDate(menu.valid_until);

  return (
    <div className="menu-detail">
      <div className="menu-detail__head">
        <div>
          <h3 className="menu-detail__title">{menu.name_ru}</h3>
          {menu.description_ru && <p className="menu-detail__desc">{menu.description_ru}</p>}
        </div>
        <div className="menu-detail__price">{formatPrice(menu.price_per_guest)} <small><T ru="/ человек" kz="/ адам" /></small></div>
      </div>

      <div className="menu-detail__facts">
        {hall && (
          <span className="menu-detail__fact">🏛️ {hall.name_ru}</span>
        )}
        {(menu.min_guests || menu.max_guests) && (
          <span className="menu-detail__fact">
            👥 {menu.min_guests || '—'}–{menu.max_guests || '—'} <T ru="гостей" kz="қонақ" />
          </span>
        )}
        {(validFrom || validUntil) && (
          <span className="menu-detail__fact">
            📅 <T ru="Действует" kz="Қолданылады" />{validFrom ? ` c ${validFrom}` : ''}{validUntil ? ` по ${validUntil}` : ''}
          </span>
        )}
      </div>

      {sections.length > 0 && (
        <>
          <div className="menu-detail__sections-head">
            <h4 className="menu-detail__sections-title"><T ru="Состав меню" kz="Мәзір құрамы" /></h4>
            <div style={{ display: 'flex', gap: 14 }}>
              <button type="button" className="admin-table__link" onClick={expandAll}><T ru="Развернуть всё" kz="Барлығын жаю" /></button>
              <button type="button" className="admin-table__link" onClick={collapseAll}><T ru="Свернуть всё" kz="Барлығын жию" /></button>
            </div>
          </div>

          <div className="menu-sections">
            {sections.map((section) => {
              const items = [...(section.items || [])].sort((a, b) => a.sort_order - b.sort_order);
              const isOpen = openIds.has(section.id);
              return (
                <div className={`menu-section${isOpen ? ' is-open' : ''}`} key={section.id}>
                  <button type="button" className="menu-section__head" onClick={() => toggle(section.id)} aria-expanded={isOpen}>
                    <span>{section.title_ru}</span>
                    <span className="menu-section__count">{items.length}</span>
                    <span className="menu-section__chevron">›</span>
                  </button>
                  {isOpen && (
                    <ul className="menu-section__items">
                      {items.map((item) => (
                        <li key={item.id}>
                          <span className="menu-section__item-name">{item.name_ru}</span>
                          {item.quantity_text && <span className="menu-section__item-qty">{item.quantity_text}</span>}
                          {item.description_ru && <span className="menu-section__item-desc">{item.description_ru}</span>}
                        </li>
                      ))}
                      {items.length === 0 && (
                        <li className="menu-section__item-empty"><T ru="Позиции пока не добавлены" kz="Позициялар әлі қосылмаған" /></li>
                      )}
                    </ul>
                  )}
                </div>
              );
            })}
          </div>
        </>
      )}

      <RestaurantMenuCalculator menu={menu} hall={hall} listing={listing} />
    </div>
  );
}
