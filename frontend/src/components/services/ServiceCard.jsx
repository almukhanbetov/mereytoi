'use client';

import { useEffect, useRef } from 'react';
import { useRouter } from 'next/navigation';
import Reveal from '@/components/Reveal';
import { useLang } from '@/context/AppProviders';
import { formatPrice, pluralRu } from '@/lib/format';
import { mediaUrl } from '@/lib/media';
import ViewCount from '@/components/services/ViewCount';
import { recordPromotionEvent, rememberAdOpen } from '@/lib/promotionApi';

// An ad impression counts only once the card was really seen: at least half
// of it in view for a second. Once per card per page view; the server drops
// repeats, the owner's own views and inflation.
function useAdImpression(promotionId) {
  const ref = useRef(null);
  useEffect(() => {
    const el = ref.current;
    if (!promotionId || !el || typeof IntersectionObserver === 'undefined') return undefined;
    let timer = null;
    let sent = false;
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (sent) return;
        if (entry.isIntersecting && entry.intersectionRatio >= 0.5) {
          timer ??= setTimeout(() => {
            sent = true;
            recordPromotionEvent(promotionId, 'impression');
            observer.disconnect();
          }, 1000);
        } else if (timer) {
          clearTimeout(timer);
          timer = null;
        }
      },
      { threshold: [0, 0.5, 1] },
    );
    observer.observe(el);
    return () => {
      if (timer) clearTimeout(timer);
      observer.disconnect();
    };
  }, [promotionId]);
  return ref;
}

export default function ServiceCard({ listing, categoryLabel, delay = 0 }) {
  const router = useRouter();
  const { lang } = useLang();
  const cover = listing.image_urls?.[0];
  // menu_count/min_menu_price_per_guest — aggregates already on the list
  // response (brief section 1's own "не загружать полный menu tree на
  // catalog page" — GET /api/listings never returns the full tree, only
  // these two numbers; see the prior stage's own ListingHandler.List).
  // A listing with zero menus (every non-restaurant category, and a
  // venues listing with no menus configured yet) simply has
  // menu_count === undefined/0, falling straight through to the
  // pre-existing plain price line below — brief section 8B's "venue без
  // menus работает как раньше."
  const hasMenus = listing.menu_count > 0;
  const promotionId = listing.promoted ? listing.promotion_id : null;
  const adRef = useAdImpression(promotionId);

  function open() {
    if (promotionId) {
      rememberAdOpen(listing.id, promotionId);
      recordPromotionEvent(promotionId, 'click');
    }
    router.push(`/services/${listing.id}`);
  }

  return (
    <Reveal
      as="article"
      className="product-card in-view"
      delay={delay}
      onClick={open}
    >
      {promotionId && (
        <>
          {/* Same box as the card: what the impression observer watches. */}
          <span ref={adRef} className="product-card__ad-area" aria-hidden="true" />
          <span className="product-card__ad">{lang === 'kz' ? 'Жарнама' : 'Реклама'}</span>
        </>
      )}
      <div
        className="product-card__media"
        style={
          cover
            ? { backgroundImage: `url(${mediaUrl(cover)})`, backgroundSize: 'cover', backgroundPosition: 'center' }
            : { '--c1': listing.color_from, '--c2': listing.color_to }
        }
      >
        {!cover && (listing.emoji || '✨')}
      </div>
      <div className="product-card__body">
        <span className="product-card__cat">{categoryLabel}</span>
        <h3 className="product-card__name">{lang === 'kz' ? listing.name_kz : listing.name_ru}</h3>
        {(listing.description_ru || listing.description_kz) && (
          <p className="product-card__desc">
            {lang === 'kz' ? listing.description_kz : listing.description_ru}
          </p>
        )}
        {listing.city && <p className="listing-card__city">📍 {listing.city}</p>}
        <ViewCount count={listing.view_count} />
        {listing.provider?.display_name && (
          <p className="product-card__provider">👤 {listing.provider.display_name}</p>
        )}
        {hasMenus ? (
          <div className="product-card__row product-card__row--menus">
            <div>
              <span className="product-card__price">
                {lang === 'kz' ? 'бастап' : 'от'} {formatPrice(listing.min_menu_price_per_guest || 0)}
                <small> {lang === 'kz' ? '/ адам' : '/ человек'}</small>
              </span>
              {listing.menu_count > 1 && (
                <span className="product-card__menu-count">
                  {listing.menu_count} {lang === 'kz'
                    ? 'мәзір нұсқасы'
                    : pluralRu(listing.menu_count, ['вариант меню', 'варианта меню', 'вариантов меню'])}
                </span>
              )}
            </div>
            {listing.rating > 0 && <span className="listing-card__rating">★ {listing.rating.toFixed(1)}</span>}
          </div>
        ) : (
          <div className="product-card__row">
            <span className="product-card__price">
              {listing.price > 0 ? formatPrice(listing.price) : (lang === 'kz' ? 'Сұраныс бойынша' : 'По запросу')}
            </span>
            {listing.rating > 0 && <span className="listing-card__rating">★ {listing.rating.toFixed(1)}</span>}
          </div>
        )}
      </div>
    </Reveal>
  );
}
