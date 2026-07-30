'use client';

import { useRouter } from 'next/navigation';
import Reveal from '@/components/Reveal';
import { useLang } from '@/context/AppProviders';
import { formatPrice } from '@/lib/format';
import { mediaUrl } from '@/lib/media';

export default function ServiceCard({ listing, categoryLabel, delay = 0 }) {
  const router = useRouter();
  const { lang } = useLang();
  const cover = listing.image_urls?.[0];

  return (
    <Reveal
      as="article"
      className="product-card in-view"
      delay={delay}
      onClick={() => router.push(`/services/${listing.id}`)}
    >
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
        {listing.city && <p className="listing-card__city">📍 {listing.city}</p>}
        <div className="product-card__row">
          <span className="product-card__price">
            {listing.price > 0 ? formatPrice(listing.price) : (lang === 'kz' ? 'Сұраныс бойынша' : 'По запросу')}
          </span>
          {listing.rating > 0 && <span className="listing-card__rating">★ {listing.rating.toFixed(1)}</span>}
        </div>
      </div>
    </Reveal>
  );
}
