'use client';

import { useCallback, useEffect, useState } from 'react';
import { T } from '@/context/AppProviders';
import { adminApi } from '@/lib/adminApi';
import RestaurantHallsTab from '@/components/admin/RestaurantHallsTab';
import RestaurantMenusTab from '@/components/admin/RestaurantMenusTab';
import ProviderServiceForm, { listingToPayload } from './ProviderServiceForm';

const TABS = [
  { key: 'basic', ru: 'Основное', kz: 'Негізгі', en: 'General' },
  { key: 'halls', ru: 'Залы', kz: 'Залдар', en: 'Halls' },
  { key: 'menus', ru: 'Меню', kz: 'Мәзір', en: 'Menus' },
];

/** The owner's restaurant management in the cabinet: the admin's own halls and
 * menus tabs, which the API already allows an owner to use. «Основное» is the
 * owner's form, with the address and the map point. */
export default function ProviderRestaurantManager({ listingId, categories, provider, onEditContact, onSaved, onClose }) {
  const [tab, setTab] = useState('basic');
  const [listing, setListing] = useState(null);
  const [error, setError] = useState('');

  const refresh = useCallback(async () => {
    const { listing: fresh } = await adminApi.listing(listingId);
    setListing(fresh);
  }, [listingId]);

  useEffect(() => {
    adminApi
      .listing(listingId)
      .then(({ listing: fresh }) => setListing(fresh))
      .catch((err) => setError(err.message || 'Не удалось загрузить ресторан'));
  }, [listingId]);

  return (
    <section className="provider-form-card" style={{ margin: '20px 0' }} data-testid="restaurant-manager">
      <div className="ws-events-head">
        <h3 className="admin-section-title" style={{ margin: 0 }}>
          {listing?.name_ru || <T ru="Ресторан" kz="Мейрамхана" en="Restaurant" />}
        </h3>
        <button type="button" className="btn btn--outline btn--sm" onClick={onClose}>
          <T ru="Закрыть" kz="Жабу" en="Close" />
        </button>
      </div>
      {error && <p className="admin-login__error">{error}</p>}
      {listing && (
        <>
          <div className="ws-tabs" role="tablist" style={{ margin: '16px 0 26px' }}>
            {TABS.map((t) => (
              <button
                key={t.key}
                type="button"
                role="tab"
                aria-selected={tab === t.key}
                className={`ws-tabs__btn${tab === t.key ? ' is-active' : ''}`}
                onClick={() => setTab(t.key)}
              >
                <T ru={t.ru} kz={t.kz} en={t.en} />
              </button>
            ))}
          </div>
          {tab === 'basic' && (
            <ProviderServiceForm
              key={listing.updated_at}
              categories={categories}
              provider={provider}
              onEditContact={onEditContact}
              categoryLocked={(listing.halls || []).length > 0 || (listing.menus || []).length > 0}
              initial={listingToPayload(listing)}
              listingId={listingId}
              onSaved={(saved) => {
                refresh();
                onSaved(saved);
              }}
              onCancel={onClose}
            />
          )}
          {tab === 'halls' && <RestaurantHallsTab listingId={listingId} halls={listing.halls || []} refresh={refresh} />}
          {tab === 'menus' && <RestaurantMenusTab listingId={listingId} menus={listing.menus || []} halls={listing.halls || []} refresh={refresh} />}
        </>
      )}
    </section>
  );
}
