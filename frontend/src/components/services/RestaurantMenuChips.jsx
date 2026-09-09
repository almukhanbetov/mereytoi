'use client';

import { useEffect, useRef, useState } from 'react';
import { T } from '@/context/AppProviders';
import { formatPrice } from '@/lib/format';

/** Brief section 7's mobile UX, applied to the menu selector specifically:
 * horizontal scroll, gold semi-transparent arrows shown only when there's
 * actually more to scroll to in that direction, a one-time soft nudge on
 * first show, and no name overflow (ellipsis-truncated inside a
 * fixed-width chip). Works identically on desktop (mouse wheel/drag/
 * trackpad already scroll a horizontal overflow container natively; the
 * arrows are just an extra affordance, not the only way to scroll). */
export default function RestaurantMenuChips({ menus, halls, viewedId, onView, compareIds, onToggleCompare }) {
  const trackRef = useRef(null);
  const [canLeft, setCanLeft] = useState(false);
  const [canRight, setCanRight] = useState(false);
  const nudgedRef = useRef(false);

  function updateArrows() {
    const el = trackRef.current;
    if (!el) return;
    setCanLeft(el.scrollLeft > 4);
    setCanRight(el.scrollLeft < el.scrollWidth - el.clientWidth - 4);
  }

  useEffect(() => {
    const el = trackRef.current;
    if (!el) return;
    updateArrows();

    const ro = new ResizeObserver(updateArrows);
    ro.observe(el);
    el.addEventListener('scroll', updateArrows, { passive: true });

    // One soft nudge the first time this is actually scrollable — a quick
    // out-and-back so it's visually obvious the row moves, without
    // stealing focus or repeating on every re-render.
    if (!nudgedRef.current && el.scrollWidth > el.clientWidth + 4) {
      nudgedRef.current = true;
      const t = setTimeout(() => {
        el.scrollBy({ left: 46, behavior: 'smooth' });
        setTimeout(() => el.scrollBy({ left: -46, behavior: 'smooth' }), 380);
      }, 500);
      return () => {
        clearTimeout(t);
        ro.disconnect();
        el.removeEventListener('scroll', updateArrows);
      };
    }

    return () => {
      ro.disconnect();
      el.removeEventListener('scroll', updateArrows);
    };
  }, [menus.length]);

  function scrollByAmount(dir) {
    trackRef.current?.scrollBy({ left: dir * 220, behavior: 'smooth' });
  }

  return (
    <div className="menu-chips">
      {canLeft && (
        <button type="button" className="menu-chips__arrow menu-chips__arrow--left" onClick={() => scrollByAmount(-1)} aria-label="Прокрутить влево">
          ‹
        </button>
      )}
      {canRight && (
        <button type="button" className="menu-chips__arrow menu-chips__arrow--right" onClick={() => scrollByAmount(1)} aria-label="Прокрутить вправо">
          ›
        </button>
      )}

      <div className="menu-chips__track" ref={trackRef}>
        {menus.map((menu) => {
          const isViewed = menu.id === viewedId;
          const isCompared = compareIds.includes(menu.id);
          const hall = halls.get(menu.hall_id);
          return (
            <div className={`menu-chip${isViewed ? ' is-active' : ''}`} key={menu.id}>
              <button type="button" className="menu-chip__body" onClick={() => onView(menu.id)}>
                <span className="menu-chip__price">{formatPrice(menu.price_per_guest)}</span>
                <span className="menu-chip__name">{menu.name_ru}</span>
                {hall && <span className="menu-chip__hall">{hall.name_ru}</span>}
              </button>
              <button
                type="button"
                className={`menu-chip__compare${isCompared ? ' is-active' : ''}`}
                onClick={() => onToggleCompare(menu.id)}
                aria-pressed={isCompared}
                title="Добавить к сравнению"
              >
                {isCompared ? '✓' : '+'}
              </button>
            </div>
          );
        })}
      </div>
      <p className="menu-chips__hint">
        <T ru="Нажмите на меню, чтобы посмотреть, или на «+», чтобы добавить к сравнению" kz="Мәзірді көру үшін басыңыз немесе салыстыру үшін «+» басыңыз" />
      </p>
    </div>
  );
}
