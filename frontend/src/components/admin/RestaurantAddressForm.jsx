'use client';

import { useEffect, useRef, useState } from 'react';
import { adminApi } from '@/lib/adminApi';
import { loadGoogleMapsScript, hasGoogleMapsKey } from '@/lib/googleMaps';

const DEFAULT_CENTER = { lat: 43.238949, lng: 76.889709 }; // Алматы, used only when nothing is saved yet

/** Brief section 1 (admin half) — Google Places autocomplete + an
 * interactive, draggable-marker preview map. Progressive enhancement: with
 * no NEXT_PUBLIC_GOOGLE_MAPS_API_KEY configured, this renders exactly the
 * plain manual city/address/lat/lng/place_id form this component already
 * had — nothing about saving changes, no script is ever requested, and no
 * admin workflow breaks for lack of a key.
 *
 * ListingHandler.Update expects the *whole* listingInput, not a partial
 * patch (same as ServiceForm's own submit already does) — so saving here
 * sends `listing` merged with just these fields changed, never touching
 * name/price/photos/etc. */
export default function RestaurantAddressForm({ listing, listingId, onSaved }) {
  const [values, setValues] = useState({
    city: listing.city || '',
    address: listing.address || '',
    latitude: listing.latitude ?? '',
    longitude: listing.longitude ?? '',
    place_id: listing.place_id || '',
  });
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState('');
  const [mapsError, setMapsError] = useState(false);

  const addressInputRef = useRef(null);
  const mapDivRef = useRef(null);
  const mapRef = useRef(null);
  const markerRef = useRef(null);

  function set(key, value) {
    setValues((v) => ({ ...v, [key]: value }));
    setSaved(false);
  }

  // Loads the script + wires up Autocomplete/Map exactly once — never if
  // no key is configured (see hasGoogleMapsKey's own doc comment). Reads
  // `values` directly rather than through a ref: this effect's deps are
  // `[]`, so its closure only ever runs once, at mount — exactly the
  // "initial saved lat/lng" moment this needs, not a live subscription to
  // every later edit (those are pushed into the already-created map/
  // marker/autocomplete instances directly, not by re-running this).
  useEffect(() => {
    if (!hasGoogleMapsKey()) return;
    let cancelled = false;

    loadGoogleMapsScript()
      .then((maps) => {
        if (cancelled || !mapDivRef.current) return;

        const hasCoords = values.latitude !== '' && values.longitude !== '';
        const center = hasCoords
          ? { lat: Number(values.latitude), lng: Number(values.longitude) }
          : DEFAULT_CENTER;

        const map = new maps.Map(mapDivRef.current, { center, zoom: hasCoords ? 15 : 11 });
        const marker = new maps.Marker({ position: center, map, draggable: true });
        // "разрешить вручную уточнить marker" (brief section 1) — dragging
        // the pin is the manual fine-tune, writing straight back into the
        // same lat/lng fields the plain form already had.
        marker.addListener('dragend', () => {
          const pos = marker.getPosition();
          set('latitude', pos.lat());
          set('longitude', pos.lng());
        });
        mapRef.current = map;
        markerRef.current = marker;

        if (addressInputRef.current) {
          const autocomplete = new maps.places.Autocomplete(addressInputRef.current, {
            fields: ['formatted_address', 'geometry', 'place_id'],
          });
          autocomplete.addListener('place_changed', () => {
            const place = autocomplete.getPlace();
            if (!place.geometry?.location) return;
            const lat = place.geometry.location.lat();
            const lng = place.geometry.location.lng();
            setValues((v) => ({
              ...v,
              address: place.formatted_address || v.address,
              latitude: lat,
              longitude: lng,
              place_id: place.place_id || v.place_id,
            }));
            setSaved(false);
            map.setCenter({ lat, lng });
            map.setZoom(16);
            marker.setPosition({ lat, lng });
          });
        }
      })
      .catch(() => {
        if (!cancelled) setMapsError(true);
      });

    return () => { cancelled = true; };
    // Runs once — the script/map/autocomplete instances are only ever
    // created a single time; later value changes are pushed into them
    // directly (marker drag, place_changed) rather than by re-running
    // this effect.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Keeps the marker/map in sync when lat/lng are edited via the plain
  // number inputs below (not just drag/autocomplete).
  useEffect(() => {
    if (!mapRef.current || !markerRef.current) return;
    if (values.latitude === '' || values.longitude === '') return;
    const pos = { lat: Number(values.latitude), lng: Number(values.longitude) };
    markerRef.current.setPosition(pos);
    mapRef.current.setCenter(pos);
  }, [values.latitude, values.longitude]);

  async function handleSubmit(e) {
    e.preventDefault();
    setSaving(true);
    setError('');
    try {
      const payload = {
        ...listing,
        city: values.city,
        address: values.address,
        latitude: values.latitude === '' ? null : Number(values.latitude),
        longitude: values.longitude === '' ? null : Number(values.longitude),
        place_id: values.place_id || null,
      };
      const { listing: updated } = await adminApi.updateListing(listingId, payload);
      onSaved?.(updated);
      setSaved(true);
      setTimeout(() => setSaved(false), 2200);
    } catch (err) {
      setError(err.message || 'Не удалось сохранить адрес');
    } finally {
      setSaving(false);
    }
  }

  const mapsOn = hasGoogleMapsKey();

  return (
    <form className="contacts__form admin-form" onSubmit={handleSubmit}>
      <div className="form-row">
        <label>
          <span>Город</span>
          <input value={values.city} onChange={(e) => set('city', e.target.value)} />
        </label>
        <label>
          <span>Адрес{mapsOn && ' (начните вводить — появятся подсказки Google)'}</span>
          <input
            ref={addressInputRef}
            value={values.address}
            onChange={(e) => set('address', e.target.value)}
            placeholder="ул. Абая, 1"
          />
        </label>
      </div>

      {mapsOn && (
        <div style={{ marginBottom: 18 }}>
          {mapsError ? (
            <p className="admin-login__error">Не удалось загрузить Google Maps — проверьте NEXT_PUBLIC_GOOGLE_MAPS_API_KEY и ограничения ключа.</p>
          ) : (
            <>
              <div ref={mapDivRef} className="admin-map-preview" />
              <p className="admin-upload-status" style={{ fontSize: 12 }}>Перетащите маркер, чтобы уточнить точку на карте</p>
            </>
          )}
        </div>
      )}

      <div className="form-row">
        <label>
          <span>Широта (latitude)</span>
          <input type="number" step="any" value={values.latitude} onChange={(e) => set('latitude', e.target.value)} placeholder="43.238293" />
        </label>
        <label>
          <span>Долгота (longitude)</span>
          <input type="number" step="any" value={values.longitude} onChange={(e) => set('longitude', e.target.value)} placeholder="76.945465" />
        </label>
      </div>

      <label>
        <span>Place ID (Google Maps{mapsOn ? '' : ', если известен — автоподбор не подключён'})</span>
        <input value={values.place_id} onChange={(e) => set('place_id', e.target.value)} placeholder="ChIJ..." readOnly={mapsOn} />
      </label>

      {error && <p className="admin-login__error">{error}</p>}

      <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
        <button type="submit" className="btn btn--gold" disabled={saving}>
          {saving ? 'Сохраняем…' : 'Сохранить адрес'}
        </button>
        <p className={`form-success${saved ? ' is-visible' : ''}`} style={{ margin: 0 }}>Сохранено</p>
      </div>
    </form>
  );
}
