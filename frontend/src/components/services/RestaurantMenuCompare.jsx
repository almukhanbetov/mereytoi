'use client';

import { T } from '@/context/AppProviders';
import { formatPrice } from '@/lib/format';

// "Напитки"/"Алкоголь" aren't real fields anywhere in this schema — there
// is no structured beverage/alcohol flag on a section/item/extra, only
// free-form names an admin typed in. This is a best-effort text match over
// that real, admin-entered data (never a guess at content that isn't
// there) — documented here and in the final report as a heuristic, not a
// guaranteed detector.
function hasDrinksSection(menu) {
  return (menu.sections || []).some((s) => /напит/i.test(s.title_ru || ''));
}
function hasAlcohol(menu) {
  const haystack = [
    ...(menu.sections || []).map((s) => s.title_ru),
    ...(menu.sections || []).flatMap((s) => (s.items || []).map((i) => i.name_ru)),
    ...(menu.extras || []).map((e) => e.title_ru),
  ].join(' ');
  return /алкогол/i.test(haystack);
}
function serviceFeeExtra(menu) {
  return (menu.extras || []).find((e) => (e.unit || '').toLowerCase() === 'percent' || e.type === 'service_fee');
}
function itemCount(menu) {
  return (menu.sections || []).reduce((s, sec) => s + (sec.items || []).length, 0);
}

const YES = <span className="menu-compare__yes">✓</span>;
const NO = <span className="menu-compare__no">—</span>;

/** Brief section 6 — only the listed high-level dimensions, deliberately
 * never a dish-by-dish text diff ("не делать сложный текстовый diff"). */
export default function RestaurantMenuCompare({ menus, halls }) {
  return (
    <div className="menu-compare-wrap">
      <table className="menu-compare">
        <thead>
          <tr>
            <th></th>
            {menus.map((m) => (
              <th key={m.id}>{m.name_ru}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          <tr>
            <td><T ru="Цена / человек" kz="Бір адамға баға" /></td>
            {menus.map((m) => <td key={m.id} className="menu-compare__price">{formatPrice(m.price_per_guest)}</td>)}
          </tr>
          <tr>
            <td><T ru="Зал" kz="Зал" /></td>
            {menus.map((m) => <td key={m.id}>{halls.get(m.hall_id)?.name_ru || NO}</td>)}
          </tr>
          <tr>
            <td><T ru="Гостей, мин–макс" kz="Қонақтар, мин–макс" /></td>
            {menus.map((m) => <td key={m.id}>{m.min_guests || m.max_guests ? `${m.min_guests || '—'}–${m.max_guests || '—'}` : NO}</td>)}
          </tr>
          <tr>
            <td><T ru="Секций" kz="Секциялар" /></td>
            {menus.map((m) => <td key={m.id}>{(m.sections || []).length}</td>)}
          </tr>
          <tr>
            <td><T ru="Позиций" kz="Позициялар" /></td>
            {menus.map((m) => <td key={m.id}>{itemCount(m)}</td>)}
          </tr>
          <tr>
            <td><T ru="Напитки" kz="Сусындар" /></td>
            {menus.map((m) => <td key={m.id}>{hasDrinksSection(m) ? YES : NO}</td>)}
          </tr>
          <tr>
            <td><T ru="Алкоголь" kz="Алкоголь" /></td>
            {menus.map((m) => <td key={m.id}>{hasAlcohol(m) ? YES : NO}</td>)}
          </tr>
          <tr>
            <td><T ru="Доп. условия" kz="Қосымша шарттар" /></td>
            {menus.map((m) => (
              <td key={m.id}>
                {(m.extras || []).length > 0 ? (m.extras || []).map((e) => e.title_ru).join(', ') : NO}
              </td>
            ))}
          </tr>
          <tr>
            <td><T ru="Сервисный сбор" kz="Қызмет ақысы" /></td>
            {menus.map((m) => {
              const fee = serviceFeeExtra(m);
              if (!fee) return <td key={m.id}>{NO}</td>;
              return (
                <td key={m.id}>{(fee.unit || '').toLowerCase() === 'percent' ? `${fee.price}%` : formatPrice(fee.price)}</td>
              );
            })}
          </tr>
        </tbody>
      </table>
    </div>
  );
}
