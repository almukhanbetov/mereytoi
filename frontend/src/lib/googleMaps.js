'use client';

// Loads Google's Maps JavaScript API (+ Places library) exactly once,
// however many admin components ask for it — memoized on a module-level
// promise rather than per-component state, since the script tag itself is
// a one-time, page-wide resource. Used ONLY by the admin restaurant
// address editor (RestaurantAddressForm.jsx); the public "Расположение"
// section never calls this at all (see .env.example's own comment on why
// it doesn't need to).
let loadPromise = null;

export function loadGoogleMapsScript() {
  if (typeof window === 'undefined') return Promise.reject(new Error('no window'));
  if (window.google?.maps?.places) return Promise.resolve(window.google.maps);
  if (loadPromise) return loadPromise;

  const key = process.env.NEXT_PUBLIC_GOOGLE_MAPS_API_KEY;
  if (!key) return Promise.reject(new Error('NEXT_PUBLIC_GOOGLE_MAPS_API_KEY is not set'));

  loadPromise = new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = `https://maps.googleapis.com/maps/api/js?key=${encodeURIComponent(key)}&libraries=places`;
    script.async = true;
    script.onload = () => resolve(window.google.maps);
    script.onerror = () => {
      loadPromise = null;
      reject(new Error('Failed to load Google Maps'));
    };
    document.head.appendChild(script);
  });
  return loadPromise;
}

export function hasGoogleMapsKey() {
  return !!process.env.NEXT_PUBLIC_GOOGLE_MAPS_API_KEY;
}
