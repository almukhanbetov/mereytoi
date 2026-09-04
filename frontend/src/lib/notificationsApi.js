'use client';

import { getUserToken } from '@/lib/authApi';

const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8090';

async function request(path, { method = 'GET', body } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  // 10B mounted the bell in AdminShell too and had to fall back to a
  // separate admin token here, since admin/customer sessions were two
  // different token stores for the same account. 10C unified that into one
  // shared token (lib/authToken.js, read via getUserToken either way), so
  // the fallback isn't needed anymore — this is the one workaround that
  // stage explicitly asked to remove once it became unnecessary.
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
