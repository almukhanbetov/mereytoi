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
  // Places-specific diagnosis, separate from mapsError above: the Maps
  // JavaScript API script can load fine (map renders) while the *Places*
  // API is disabled/unbilled/restricted for the same key — a distinct,
  // independently-enabled API in Google Cloud Console. When that happens
  // the Autocomplete widget fails silently: no dropdown, no error, nothing
  // for the admin to act on. This surfaces Google's own status code
  // instead of leaving that failure invisible.
  const [placesStatus, setPlacesStatus] = useState(null);

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
          // Bias suggestions toward wherever the admin is actually looking
          // on the map (Google's own recommended usage) — also doubles as
          // a cheap, one-off diagnostic: if Places predictions are blocked
          // (API not enabled / no billing / key restricted to Maps JS
          // only), AutocompleteService reports it via `status`, which the
          // map-rendering-fine / no-dropdown symptom never otherwise
          // reveals to the admin.
          autocomplete.bindTo('bounds', map);
          if (maps.places.AutocompleteService) {
            new maps.places.AutocompleteService().getPlacePredictions(
              { input: 'Алматы' },
              (_predictions, status) => {
                if (cancelled) return;
                const ok = status === maps.places.PlacesServiceStatus.OK
                  || status === maps.places.PlacesServiceStatus.ZERO_RESULTS;
                setPlacesStatus(ok ? null : status);
              }
            );
          }
          autocomplete.addListener('place_changed', () => {
            const place = autocomplete.getPlace();
            const loc = place.geometry?.location;
            // Capture the chosen address + place_id even when the Place
            // Details response carried no geometry (e.g. the key doesn't
            // have Places API / geocoding enabled). Without this, a
            // suggestion the admin clearly selected is silently dropped on
            // save: the Autocomplete widget only writes it into the input's
            // raw DOM value, which this controlled field never sees.
            setValues((v) => ({
              ...v,
              address: place.formatted_address || place.name || v.address,
              // place_id is now a read-only, autocomplete-only field (see
              // the input below) — it must always reflect the currently
              // selected place, never a stale value from a previous pick,
              // so a place with no place_id clears it rather than keeping
              // an old one that no longer matches `address`.
              place_id: place.place_id || '',
              ...(loc ? { latitude: loc.lat(), longitude: loc.lng() } : {}),
            }));
            setSaved(false);
            if (loc) {
              map.setCenter({ lat: loc.lat(), lng: loc.lng() });
              map.setZoom(16);
              marker.setPosition({ lat: loc.lat(), lng: loc.lng() });
            }
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
      // The address field is controlled, but Google's Places Autocomplete
      // writes the picked address straight into the DOM node without firing
      // React's tracked onChange — so `values.address` can lag behind what
      // the admin actually sees. Trust the live input value.
      const address = (addressInputRef.current?.value ?? values.address ?? '').trim();
      const payload = {
        ...listing,
        city: values.city,
        address,
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
            autoComplete="off"
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
              {placesStatus && (
                <p className="admin-login__error" style={{ marginTop: 8 }}>
                  Подсказки адреса Google не работают (Places API: {placesStatus}). Карта грузится через отдельный
                  Maps JavaScript API — включите Places API (и биллинг) для этого ключа в Google Cloud Console,
                  либо задайте координаты вручную/перетаскиванием маркера.
                </p>
              )}
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
        <span>Google Place ID</span>
        <input
          value={values.place_id}
          placeholder="Заполнится автоматически"
          readOnly
          style={{ cursor: 'default', background: 'var(--surface-tint)', color: 'var(--text-muted)' }}
        />
        <small style={{ fontWeight: 400, fontSize: 12, color: 'var(--text-muted)', marginTop: 2 }}>
          Заполняется автоматически после выбора адреса из подсказок Google
        </small>
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
