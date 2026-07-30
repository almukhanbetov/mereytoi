'use client';

const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8090';

export async function createBooking(payload, token) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  const res = await fetch(`${API_URL}/api/bookings`, {
    method: 'POST',
    headers,
    body: JSON.stringify(payload),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(data.error || `Request failed (${res.status})`);
  }
  return data;
}

export async function lookupBookings(refs) {
  if (!refs || refs.length === 0) return [];
  const res = await fetch(`${API_URL}/api/bookings/lookup?ref=${refs.join(',')}`);
  const data = await res.json().catch(() => ({}));
  if (!res.ok) return [];
  return data.bookings || [];
}
