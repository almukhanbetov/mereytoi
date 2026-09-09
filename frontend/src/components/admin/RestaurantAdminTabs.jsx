'use client';

import { useCallback, useState } from 'react';
import { adminApi } from '@/lib/adminApi';
import ServiceForm from './ServiceForm';
import RestaurantHallsTab from './RestaurantHallsTab';
import RestaurantMenusTab from './RestaurantMenusTab';
import RestaurantAddressForm from './RestaurantAddressForm';

const TABS = [
  { key: 'basic', label: 'Основное' },
  { key: 'halls', label: 'Залы' },
  { key: 'menus', label: 'Меню' },
  { key: 'address', label: 'Адрес и расположение' },
];

/** Brief section 1 — the 4-tab shell shown only for a restaurant/venue
 * Listing being edited (see lib/restaurantCategory.js's own doc comment
 * on how that's detected). "Основное" is the *exact same* ServiceForm
 * every other category's edit page already uses — reused unchanged, not
 * forked, per the brief's "переиспользовать существующую админку".
 *
 * Reuses .ws-tabs (already the tab-bar style everywhere else in this
 * codebase, e.g. profile/page.js's "Мои мероприятия"/"Аккаунт") instead
 * of inventing a second tab visual language. */
export default function RestaurantAdminTabs({ categories, listing, listingId }) {
  const [tab, setTab] = useState('basic');
  const [current, setCurrent] = useState(listing);

  const refresh = useCallback(async () => {
    const { listing: fresh } = await adminApi.listing(listingId);
    setCurrent(fresh);
  }, [listingId]);

  return (
    <div>
      <div className="ws-tabs" role="tablist" style={{ marginBottom: 26 }}>
        {TABS.map((t) => (
          <button
            key={t.key}
            type="button"
            role="tab"
            aria-selected={tab === t.key}
            className={`ws-tabs__btn${tab === t.key ? ' is-active' : ''}`}
            onClick={() => setTab(t.key)}
          >
            {t.label}
          </button>
        ))}
      </div>

      {tab === 'basic' && <ServiceForm categories={categories} initial={current} listingId={listingId} />}
      {tab === 'halls' && <RestaurantHallsTab listingId={listingId} halls={current.halls || []} refresh={refresh} />}
      {tab === 'menus' && <RestaurantMenusTab listingId={listingId} menus={current.menus || []} halls={current.halls || []} refresh={refresh} />}
      {tab === 'address' && <RestaurantAddressForm listing={current} listingId={listingId} onSaved={setCurrent} />}
    </div>
  );
}
