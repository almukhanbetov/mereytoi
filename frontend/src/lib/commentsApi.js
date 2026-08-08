'use client';

import { getUserToken } from '@/lib/authApi';

const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8090';

async function request(path, { method = 'GET', body, auth = false } = {}) {
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
    throw new Error(data.error || `Request failed (${res.status})`);
  }
  return data;
}

export const commentsApi = {
  list: (listingId) => request(`/api/listings/${listingId}/comments`),
  create: (listingId, rating, text) =>
    request(`/api/listings/${listingId}/comments`, { method: 'POST', body: { rating, text }, auth: true }),
};
