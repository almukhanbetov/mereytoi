'use client';

import { T } from '@/context/AppProviders';

/** Brief section 1 (public half) — "Расположение". Deliberately loads no
 * Google JS SDK and needs no API key at all: Google's own key-less embed
 * (`google.com/maps?...&output=embed` in a plain <iframe>) and a plain
 * maps.google.com directions link cover exactly what's asked for (a
 * preview map with a marker, and a "Построить маршрут" button) without
 * making an ordinary service — or even a venues listing with no saved
 * coordinates — depend on Google Maps in any way (brief section 9).
 *
 * No geocoding ever happens here — only whatever lat/lng/place_id was
 * already saved by the admin gets used (brief section 1's own
 * "не делать geocoding при каждом открытии public page"). */
export default function RestaurantLocation({ listing }) {
  const hasCoords = typeof listing.latitude === 'number' && typeof listing.longitude === 'number';
  const addressText = listing.address || listing.city;

  // Nothing at all to show — the whole block simply doesn't render (brief
  // section 9's fallback), rather than an empty "Расположение" heading.
  if (!addressText && !hasCoords) return null;

  const directionsUrl = listing.place_id
    ? `https://www.google.com/maps/dir/?api=1&destination=${encodeURIComponent(addressText || '')}&destination_place_id=${encodeURIComponent(listing.place_id)}`
    : hasCoords
      ? `https://www.google.com/maps/dir/?api=1&destination=${listing.latitude},${listing.longitude}`
      : `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(addressText)}`;

  return (
    <section className="restaurant-location">
      <div className="container">
        <h2 className="section-title" style={{ textAlign: 'left' }}><T ru="Расположение" kz="Орналасуы" /></h2>

        {addressText && <p className="restaurant-location__address">📍 {addressText}</p>}

        {hasCoords && (
          <div className="restaurant-location__map">
            <iframe
              title="map"
              src={`https://www.google.com/maps?q=${listing.latitude},${listing.longitude}&output=embed`}
              loading="lazy"
              referrerPolicy="no-referrer-when-downgrade"
            />
          </div>
        )}

        <a href={directionsUrl} target="_blank" rel="noopener noreferrer" className="btn btn--outline" style={{ marginTop: 16 }}>
          <T ru="Построить маршрут" kz="Бағыт салу" />
        </a>
      </div>
    </section>
  );
}
