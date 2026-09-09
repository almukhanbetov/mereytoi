'use client';

import { useMemo, useState } from 'react';
import { T, useCart, useLang, useManagerChat } from '@/context/AppProviders';
import { formatPrice } from '@/lib/format';
import { flyToCart } from '@/lib/flyToCart';
import AddToEventMenu from '@/components/profile/AddToEventMenu';

// unit is a free-form string set by the admin (brief's own preset list:
// kids_table/artists_table/service_fee/rental/corkage/other, each with its
// own Unit text) — "percent" is the one value this calculator treats
// specially (a service charge computed as % of the running subtotal,
// never a hardcoded number); everything else (per_guest, per_item, flat,
// or simply left blank) is priced the same way — per_guest scales with
// guest count, anything else is added once, flat. Nothing here invents a
// percentage or price that isn't already in the API response.
function isPercentUnit(unit) {
  return (unit || '').trim().toLowerCase() === 'percent';
}
function isPerGuestUnit(unit) {
  return (unit || '').trim().toLowerCase() === 'per_guest';
}

/** Brief sections 4 + 5, combined into one block: the extras list *is* the
 * calculator's own "what to include" selector — showing it twice (once as
 * a plain "Дополнительно" list, once again as calculator checkboxes)
 * would just be the same information laid out two different ways.
 *
 * Final integration stage adds the three action buttons at the bottom —
 * Cart (B), "Мой той" (C), and manager-chat context (F) — all reading off
 * this exact calculator state (guests/selected extras/estimated total),
 * so whichever channel the customer uses next, the number they see here
 * is the number that travels with them. */
export default function RestaurantMenuCalculator({ menu, hall, listing }) {
  const { lang } = useLang();
  const { addItem } = useCart();
  const { openChat } = useManagerChat();
  const extras = [...(menu.extras || [])].sort((a, b) => a.sort_order - b.sort_order);
  const minGuests = menu.min_guests || 1;
  const maxGuests = menu.max_guests || undefined;

  const [guests, setGuests] = useState(minGuests || 50);
  const [selectedExtraIds, setSelectedExtraIds] = useState(() => new Set());
  const [added, setAdded] = useState(false);

  function toggleExtra(id) {
    setSelectedExtraIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  const breakdown = useMemo(() => {
    const subtotal = menu.price_per_guest * guests;
    const flatExtras = [];
    const percentExtras = [];
    for (const extra of extras) {
      if (!selectedExtraIds.has(extra.id)) continue;
      if (isPercentUnit(extra.unit)) {
        percentExtras.push(extra);
      } else {
        const amount = isPerGuestUnit(extra.unit) ? extra.price * guests : extra.price;
        flatExtras.push({ extra, amount });
      }
    }
    const flatSum = flatExtras.reduce((s, f) => s + f.amount, 0);
    const beforePercent = subtotal + flatSum;
    const percentLines = percentExtras.map((extra) => ({ extra, amount: Math.round((beforePercent * extra.price) / 100) }));
    const percentSum = percentLines.reduce((s, p) => s + p.amount, 0);
    const total = beforePercent + percentSum;
    const selected = [...flatExtras.map((f) => f.extra), ...percentLines.map((p) => p.extra)]
      .map((extra) => ({ title: extra.title_ru, price: extra.price, unit: extra.unit || '' }));
    return { subtotal, flatExtras, percentLines, total, selected };
  }, [menu.price_per_guest, guests, extras, selectedExtraIds]);

  const listingName = listing ? (lang === 'kz' ? listing.name_kz : listing.name_ru) : '';
  const categoryName = listing?.category ? (lang === 'kz' ? listing.category.name_kz : listing.category.name_ru) : '';

  function handleAddToCart(e) {
    if (!listing) return;
    addItem({
      listingId: listing.id,
      name: `${listingName} · ${menu.name_ru}`,
      category: categoryName,
      emoji: listing.emoji,
      colorFrom: listing.color_from,
      colorTo: listing.color_to,
      image: (listing.image_urls || [])[0] || null,
      unitPrice: menu.price_per_guest,
      guests,
      totalPrice: breakdown.total,
      hallId: hall?.id || menu.hall_id || null,
      hallName: hall?.name_ru || null,
      menuId: menu.id,
      menuName: menu.name_ru,
      menuPricePerGuest: menu.price_per_guest,
      selectedExtras: breakdown.selected,
      estimatedTotal: breakdown.total,
    });
    flyToCart(e.currentTarget);
    setAdded(true);
    setTimeout(() => setAdded(false), 2200);
  }

  function handleAskManager() {
    if (!listing) return;
    openChat({
      listingId: listing.id,
      listingName,
      listingPrice: menu.price_per_guest,
      categoryName,
      hallId: hall?.id || menu.hall_id || null,
      hallName: hall?.name_ru || null,
      menuId: menu.id,
      menuName: menu.name_ru,
      menuPricePerGuest: menu.price_per_guest,
      guestCount: guests,
      estimatedTotal: breakdown.total,
    });
  }

  return (
    <div className="menu-calc">
      {extras.length > 0 && (
        <>
          <h4 className="menu-detail__sections-title" style={{ marginBottom: 12 }}><T ru="Дополнительно" kz="Қосымша" /></h4>
          <div className="menu-extras">
            {extras.map((extra) => (
              <label className="menu-extra" key={extra.id}>
                <input type="checkbox" checked={selectedExtraIds.has(extra.id)} onChange={() => toggleExtra(extra.id)} />
                <span className="menu-extra__title">{extra.title_ru}</span>
                <span className="menu-extra__price">
                  {isPercentUnit(extra.unit)
                    ? `${extra.price}%`
                    : `${formatPrice(extra.price)}${isPerGuestUnit(extra.unit) ? ' / чел.' : ''}`}
                </span>
              </label>
            ))}
          </div>
        </>
      )}

      <h4 className="menu-detail__sections-title" style={{ marginTop: 22, marginBottom: 12 }}><T ru="Калькулятор" kz="Калькулятор" /></h4>

      <div className="booking-calc">
        <div className="booking-calc__row">
          <span className="booking-calc__label"><T ru="Количество гостей" kz="Қонақтар саны" /></span>
          <span className="booking-calc__guests">{guests} <T ru="чел." kz="адам" /></span>
        </div>
        <input
          type="range"
          min={minGuests}
          max={maxGuests || Math.max(minGuests * 4, 200)}
          value={guests}
          onChange={(e) => setGuests(Number(e.target.value))}
        />
        <div className="booking-calc__range-labels">
          <span>{minGuests} <T ru="чел." kz="адам" /></span>
          <span>{maxGuests || Math.max(minGuests * 4, 200)} <T ru="чел." kz="адам" /></span>
        </div>

        <div className="menu-calc__formula">
          <div className="menu-calc__line">
            <span>{guests} <T ru="гостей" kz="қонақ" /> × {formatPrice(menu.price_per_guest)}</span>
            <span>{formatPrice(breakdown.subtotal)}</span>
          </div>
          {breakdown.flatExtras.map(({ extra, amount }) => (
            <div className="menu-calc__line menu-calc__line--extra" key={extra.id}>
              <span>+ {extra.title_ru}</span>
              <span>+ {formatPrice(amount)}</span>
            </div>
          ))}
          {breakdown.percentLines.map(({ extra, amount }) => (
            <div className="menu-calc__line menu-calc__line--extra" key={extra.id}>
              <span>+ {extra.title_ru} ({extra.price}%)</span>
              <span>+ {formatPrice(amount)}</span>
            </div>
          ))}
        </div>

        <div className="booking-calc__total">
          <div>
            <div className="booking-calc__total-label"><T ru="Итого" kz="Барлығы" /></div>
          </div>
          <div className="booking-calc__total-value">{formatPrice(breakdown.total)}</div>
        </div>

        {listing && (
          <div className="menu-calc__actions">
            <button type="button" className="btn btn--gold" onClick={handleAddToCart}>
              <T ru="Добавить это меню в корзину" kz="Осы мәзірді себетке қосу" />
            </button>
            <AddToEventMenu
              listingId={listing.id}
              variant={{ hallId: hall?.id || menu.hall_id || null, menuId: menu.id, guests, estimatedTotal: breakdown.total }}
            />
            <button type="button" className="btn btn--outline" onClick={handleAskManager}>
              <T ru="Спросить менеджера" kz="Менеджерден сұрау" />
            </button>
          </div>
        )}
        <p className={`booking-added${added ? ' is-visible' : ''}`}>
          <T ru="Добавлено в корзину!" kz="Себетке қосылды!" />
        </p>
      </div>
    </div>
  );
}
