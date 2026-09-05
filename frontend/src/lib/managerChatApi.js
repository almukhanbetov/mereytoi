'use client';

import { getUserToken } from '@/lib/authApi';

const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8090';

async function request(path, { method = 'GET', body } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  const token = getUserToken();
  if (token) headers.Authorization = `Bearer ${token}`;

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

// Real two-way manager chat — authenticated customers only (see
// backend/internal/models/manager_chat.go's own doc comment for why: this
// stage adds a genuine persistent conversation, and a guest has no stable
// identity to hang one off of). Guests keep using bookingApi's
// createBooking, unchanged — see FloatingManagerWidget.jsx.
export const managerChatApi = {
  // Finds-or-creates the one open conversation for this exact context
  // (event_id/listing_id) and posts `message` into it — safe to call every
  // time the widget opens with a context, not just once.
  start: (message, { eventId, listingId } = {}) =>
    request('/api/manager-chat/start', {
      method: 'POST',
      body: { message, event_id: eventId ?? null, listing_id: listingId ?? null },
    }),
  get: (id) => request(`/api/manager-chat/${id}`),
  addMessage: (id, body) => request(`/api/manager-chat/${id}/messages`, { method: 'POST', body: { body } }),
};
