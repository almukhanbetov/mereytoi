'use client';

import { getUserToken } from '@/lib/authApi';
import { getToken as getAdminToken } from '@/lib/adminApi';

const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8090';

async function request(path, { method = 'GET', body } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  // The bell is mounted both in the customer Header and (10B) in AdminShell
  // — an admin session only ever stores a token under the separate
  // mereytoi-admin-token key, but it's the exact same /api/auth/login JWT,
  // so falling back to it here is correct, not a workaround: one account,
  // one notification center, just two historically-separate login flows.
  const token = getUserToken() || getAdminToken();
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

// In-app notification center — see backend/internal/models/notification.go.
export const notificationsApi = {
  list: ({ unread, page = 1, limit = 20 } = {}) => {
    const params = new URLSearchParams({ page: String(page), limit: String(limit) });
    if (unread) params.set('unread', 'true');
    return request(`/api/notifications?${params.toString()}`);
  },
  unreadCount: () => request('/api/notifications/unread-count'),
  markRead: (id) => request(`/api/notifications/${id}/read`, { method: 'POST' }),
  markAllRead: () => request('/api/notifications/read-all', { method: 'POST' }),
};
