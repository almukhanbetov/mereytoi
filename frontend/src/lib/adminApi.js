'use client';

// 10C: the admin area used to keep its own separate token under
// 'mereytoi-admin-token' — a second, parallel session for the exact same
// /api/auth/login account. That's gone; this now reads/writes the one
// shared token in lib/authToken.js, still exported here under the original
// getToken/setToken/clearToken names so nothing importing them needed to
// change (this file's own uploadImages/uploadVideo below included).
import { getToken, setToken, clearToken } from '@/lib/authToken';

export { getToken, setToken, clearToken };

const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8090';

async function request(path, { method = 'GET', body, auth = false } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (auth) {
    const token = getToken();
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

async function uploadImages(files) {
  const token = getToken();
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

async function uploadVideo(file) {
  const token = getToken();
  const formData = new FormData();
  formData.append('video', file);

  const res = await fetch(`${API_URL}/api/uploads/video`, {
    method: 'POST',
    headers: token ? { Authorization: `Bearer ${token}` } : undefined,
    body: formData,
  });

  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(data.error || `Upload failed (${res.status})`);
  }
  return data.url;
}

export const adminApi = {
  login: (identifier, password) => {
    const trimmed = identifier.trim();
    const body = trimmed.includes('@') ? { email: trimmed, password } : { phone: trimmed, password };
    return request('/api/auth/login', { method: 'POST', body });
  },
  me: () => request('/api/auth/me', { auth: true }),

  categories: () => request('/api/categories'),
  createCategory: (payload) => request('/api/categories', { method: 'POST', body: payload, auth: true }),
  updateCategory: (id, payload) => request(`/api/categories/${id}`, { method: 'PUT', body: payload, auth: true }),
  deleteCategory: (id) => request(`/api/categories/${id}`, { method: 'DELETE', auth: true }),
  listings: () => request('/api/listings'),
  listing: (id) => request(`/api/listings/${id}`),
  createListing: (payload) => request('/api/listings', { method: 'POST', body: payload, auth: true }),
  updateListing: (id, payload) => request(`/api/listings/${id}`, { method: 'PUT', body: payload, auth: true }),
  deleteListing: (id) => request(`/api/listings/${id}`, { method: 'DELETE', auth: true }),
  uploadImages,
  uploadVideo,

  bookings: () => request('/api/bookings', { auth: true }),
  updateBookingStatus: (id, status) => request(`/api/bookings/${id}`, { method: 'PUT', body: { status }, auth: true }),
  updateBookingPaid: (id, paid) => request(`/api/bookings/${id}`, { method: 'PUT', body: { paid }, auth: true }),
  deleteBooking: (id) => request(`/api/bookings/${id}`, { method: 'DELETE', auth: true }),

  comments: (approved) => request(`/api/comments${approved !== undefined ? `?approved=${approved}` : ''}`, { auth: true }),
  approveComment: (id, approved) => request(`/api/comments/${id}`, { method: 'PUT', body: { approved }, auth: true }),
  deleteComment: (id) => request(`/api/comments/${id}`, { method: 'DELETE', auth: true }),

  clients: () => request('/api/clients'),
  createClient: (payload) => request('/api/clients', { method: 'POST', body: payload, auth: true }),
  updateClient: (id, payload) => request(`/api/clients/${id}`, { method: 'PUT', body: payload, auth: true }),
  deleteClient: (id) => request(`/api/clients/${id}`, { method: 'DELETE', auth: true }),

  siteStatistics: () => request('/api/site-statistics'),
  updateSiteStatistics: (payload) => request('/api/site-statistics', { method: 'PUT', body: payload, auth: true }),

  eventRequests: (status) => request(`/api/admin/event-requests${status && status !== 'all' ? `?status=${status}` : ''}`, { auth: true }),
  eventRequest: (id) => request(`/api/admin/event-requests/${id}`, { auth: true }),
  updateEventRequestStatus: (id, status, managerComment) =>
    request(`/api/admin/event-requests/${id}/status`, { method: 'POST', body: { status, manager_comment: managerComment }, auth: true }),

  // Manager chat dialogs (brief section 24) — deliberately not a separate
  // CRM: list/detail/reply/status, same shape as eventRequests above.
  managerChats: (status) => request(`/api/admin/manager-chat${status && status !== 'all' ? `?status=${status}` : ''}`, { auth: true }),
  managerChat: (id) => request(`/api/admin/manager-chat/${id}`, { auth: true }),
  replyManagerChat: (id, body) => request(`/api/admin/manager-chat/${id}/messages`, { method: 'POST', body: { body }, auth: true }),
  updateManagerChatStatus: (id, status) => request(`/api/admin/manager-chat/${id}/status`, { method: 'POST', body: { status }, auth: true }),
};
