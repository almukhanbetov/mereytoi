'use client';

import { getUserToken } from '@/lib/authApi';

const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8090';

// "Стать услугодателем" / "Мои услуги" — Этап 11. A regular user's optional
// provider profile, kept deliberately separate from adminApi.js (that file
// is the *admin's* CRUD over every listing; this one is a plain user
// managing only their own — same backend ownership check either way, see
// backend/internal/middleware/listing.go's RequireListingAccess). The
// listing update/delete/upload calls below hit the exact same
// /api/listings/:id and /api/uploads endpoints adminApi.js does — no
// parallel backend surface, just a second thin client because this file
// lives in the regular user's profile area, not /admin.
async function request(path, { method = 'GET', body, auth = true } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (auth) {
    const token = getUserToken();
    if (token) headers.Authorization = `Bearer ${token}`;
  }

  const res = await fetch(`${API_URL}${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });

  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    const err = new Error(data.error || `Request failed (${res.status})`);
    err.status = res.status;
    throw err;
  }
  return data;
}

async function uploadImages(files) {
  const token = getUserToken();
  const formData = new FormData();
  Array.from(files).forEach((file) => formData.append('files', file));

  const res = await fetch(`${API_URL}/api/uploads`, {
    method: 'POST',
    headers: token ? { Authorization: `Bearer ${token}` } : undefined,
    body: formData,
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(data.error || `Upload failed (${res.status})`);
  }
  return data.urls;
}

export const providerApi = {
  categories: () => request('/api/categories', { auth: false }),

  // Provider profile itself.
  me: () => request('/api/provider/me'),
  create: (payload) => request('/api/provider', { method: 'POST', body: payload }),
  update: (payload) => request('/api/provider/me', { method: 'PUT', body: payload }),

  // "Мои услуги" — GET reuses the same endpoint the (Flutter-only so far)
  // restaurant-admin "Мои рестораны" flow already established; create is
  // the one genuinely new self-serve endpoint (see
  // backend/internal/handlers/listing_handler.go's CreateOwn); update/
  // delete reuse the exact same /api/listings/:id admin uses, now also
  // reachable by an owner/manager via RequireListingAccess.
  myListings: () => request('/api/users/me/listings'),
  createListing: (payload) => request('/api/provider/me/listings', { method: 'POST', body: payload }),
  updateListing: (id, payload) => request(`/api/listings/${id}`, { method: 'PUT', body: payload }),
  deleteListing: (id) => request(`/api/listings/${id}`, { method: 'DELETE' }),
  listing: (id) => request(`/api/listings/${id}`, { auth: false }),

  uploadImages,
};
