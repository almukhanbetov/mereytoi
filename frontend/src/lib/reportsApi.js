'use client';

import { getToken } from '@/lib/authToken';

const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8090';

async function request(path, { method = 'GET', body } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  const token = getToken();
  if (token) headers.Authorization = `Bearer ${token}`;
  const res = await fetch(`${API_URL}${path}`, { method, headers, body: body ? JSON.stringify(body) : undefined });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    const err = new Error(data.error || `Request failed (${res.status})`);
    err.status = res.status;
    err.data = data;
    throw err;
  }
  return data;
}

// Users' complaints — POST /api/reports, GET /api/reports/mine (signed in).
export const reportsApi = {
  create: ({ targetType, targetId, reason, details }) =>
    request('/api/reports', {
      method: 'POST',
      body: { target_type: targetType, target_id: targetId, reason, details: details || '' },
    }),
  mine: () => request('/api/reports/mine'),
};
