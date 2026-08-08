'use client';

const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8090';
const TOKEN_KEY = 'mereytoi-user-token';

export function getUserToken() {
  if (typeof window === 'undefined') return null;
  return localStorage.getItem(TOKEN_KEY);
}

export function setUserToken(token) {
  localStorage.setItem(TOKEN_KEY, token);
}

export function clearUserToken() {
  localStorage.removeItem(TOKEN_KEY);
}

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

export const authApi = {
  register: (name, email, phone, password) =>
    request('/api/auth/register', { method: 'POST', body: { name, email, phone, password } }),
  login: (identifier, password) => {
    const trimmed = identifier.trim();
    const body = trimmed.includes('@') ? { email: trimmed, password } : { phone: trimmed, password };
    return request('/api/auth/login', { method: 'POST', body });
  },
  me: () => request('/api/auth/me', { auth: true }),
  updateMe: (name, phone) => request('/api/auth/me', { method: 'PUT', body: { name, phone }, auth: true }),
  myBookings: () => request('/api/users/me/bookings', { auth: true }),
  deleteMyBooking: (id) => request(`/api/users/me/bookings/${id}`, { method: 'DELETE', auth: true }),
};
