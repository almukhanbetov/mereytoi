'use client';

import { useMemo, useState } from 'react';
import Reveal from '@/components/Reveal';
import { T } from '@/context/AppProviders';
import RestaurantMenuChips from './RestaurantMenuChips';
import RestaurantMenuDetail from './RestaurantMenuDetail';
import RestaurantMenuCompare from './RestaurantMenuCompare';

/** "Банкетные меню" — brief section 2. Renders nothing unless the listing
 * actually has active menus (see the guard in ServiceDetail.jsx that
 * decides whether to even mount this at all, restricted to the venues
 * category). Inactive menus/halls are filtered out here, client-side —
 * the public detail endpoint (GET /api/listings/:id) returns the *full*
 * tree including drafts because the same handler also serves the admin
 * editor (see backend's own loadListingTree doc comment); this stage is
 * public-UI-only, so rather than touch that shared backend code, "inactive
 * menu не показывается" (brief section 8E) is enforced purely by what
 * gets rendered here. */
export default function RestaurantMenus({ listing }) {
  const activeMenus = useMemo(
    () => (listing.menus || []).filter((m) => m.is_active).sort((a, b) => a.sort_order - b.sort_order),
    [listing.menus]
  );
  const activeHalls = useMemo(
    () => (listing.halls || []).filter((h) => h.is_active),
    [listing.halls]
  );

  const [viewedId, setViewedId] = useState(activeMenus[0]?.id ?? null);
  const [compareIds, setCompareIds] = useState([]);
  const [comparing, setComparing] = useState(false);

  if (activeMenus.length === 0) return null;

  const viewedMenu = activeMenus.find((m) => m.id === viewedId) || activeMenus[0];
  const hallById = new Map(activeHalls.map((h) => [h.id, h]));

  function toggleCompare(id) {
    setCompareIds((prev) => {
      if (prev.includes(id)) return prev.filter((x) => x !== id);
      if (prev.length >= 3) return prev; // brief section 6 — "выбрать 2–3 меню"
      return [...prev, id];
    });
  }

  return (
    <section className="restaurant-menus">
      <div className="container">
        <Reveal as="p" className="section-eyebrow"><T ru="МЕНЮ" kz="МЕНЮ" /></Reveal>
        <Reveal as="h2" className="section-title" style={{ textAlign: 'left' }}>
          <T ru="Банкетные меню" kz="Банкет мәзірлері" />
        </Reveal>

        <RestaurantMenuChips
          menus={activeMenus}
          halls={hallById}
          viewedId={viewedMenu.id}
          onView={(id) => { setViewedId(id); setComparing(false); }}
          compareIds={compareIds}
          onToggleCompare={toggleCompare}
        />

        {compareIds.length >= 2 && (
          <div className="restaurant-menus__compare-bar">
            <span className="booking-workspace-cta__text" style={{ margin: 0 }}>
              <T ru={`Выбрано меню для сравнения: ${compareIds.length}`} kz={`Салыстыруға таңдалды: ${compareIds.length}`} />
            </span>
            <button type="button" className="btn btn--outline btn--sm" onClick={() => setComparing((v) => !v)}>
              {comparing ? <T ru="Скрыть сравнение" kz="Салыстыруды жасыру" /> : <T ru="Сравнить меню" kz="Мәзірлерді салыстыру" />}
            </button>
          </div>
        )}

        {comparing && compareIds.length >= 2 ? (
          <RestaurantMenuCompare
            menus={activeMenus.filter((m) => compareIds.includes(m.id))}
            halls={hallById}
          />
        ) : (
          <RestaurantMenuDetail menu={viewedMenu} hall={hallById.get(viewedMenu.hall_id)} listing={listing} />
        )}
      </div>
    </section>
  );
}
