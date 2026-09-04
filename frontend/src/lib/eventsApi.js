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

// "Мой той" — the collaborative event workspace API. Every call carries the
// user's own bearer token; server-side membership/role checks (not this
// client) are what actually enforce who can see or do what — see
// backend/internal/middleware/event.go.
export const eventsApi = {
  list: () => request('/api/events'),
  create: (input) => request('/api/events', { method: 'POST', body: input }),
  get: (id) => request(`/api/events/${id}`),
  update: (id, input) => request(`/api/events/${id}`, { method: 'PUT', body: input }),
  remove: (id) => request(`/api/events/${id}`, { method: 'DELETE' }),
  summary: (id) => request(`/api/events/${id}/summary`),

  members: (id) => request(`/api/events/${id}/members`),
  changeRole: (id, userId, role) => request(`/api/events/${id}/members/${userId}`, { method: 'PUT', body: { role } }),
  removeMember: (id, userId) => request(`/api/events/${id}/members/${userId}`, { method: 'DELETE' }),

  // email is optional (stage 11A) — the link-based invitation is created
  // identically either way; when given, the backend also emails it there.
  createInvitation: (id, role, email) => request(`/api/events/${id}/invitations`, { method: 'POST', body: email ? { role, email } : { role } }),
  listInvitations: (id) => request(`/api/events/${id}/invitations`),
  revokeInvitation: (id, invId) => request(`/api/events/${id}/invitations/${invId}`, { method: 'DELETE' }),

  candidates: (id) => request(`/api/events/${id}/candidates`),
  addCandidate: (id, listingId) => request(`/api/events/${id}/candidates`, { method: 'POST', body: { listing_id: listingId } }),
  updateCandidateStatus: (id, candidateId, status) =>
    request(`/api/events/${id}/candidates/${candidateId}`, { method: 'PUT', body: { status } }),
  removeCandidate: (id, candidateId) => request(`/api/events/${id}/candidates/${candidateId}`, { method: 'DELETE' }),
  vote: (id, candidateId, value) => request(`/api/events/${id}/candidates/${candidateId}/vote`, { method: 'POST', body: { value } }),

  comments: (id, candidateId) => request(`/api/events/${id}/comments${candidateId ? `?candidate_id=${candidateId}` : ''}`),
  addComment: (id, body, candidateId) =>
    request(`/api/events/${id}/comments`, { method: 'POST', body: { body, candidate_id: candidateId ?? null } }),
  deleteComment: (id, commentId) => request(`/api/events/${id}/comments/${commentId}`, { method: 'DELETE' }),

  activity: (id) => request(`/api/events/${id}/activity`),

  tasks: (id) => request(`/api/events/${id}/tasks`),
  createTask: (id, input) => request(`/api/events/${id}/tasks`, { method: 'POST', body: input }),
  updateTask: (id, taskId, input) => request(`/api/events/${id}/tasks/${taskId}`, { method: 'PUT', body: input }),
  deleteTask: (id, taskId) => request(`/api/events/${id}/tasks/${taskId}`, { method: 'DELETE' }),

  previewInvitation: (token) => request(`/api/invitations/${token}`),
  acceptInvitation: (token) => request(`/api/invitations/${token}/accept`, { method: 'POST' }),

  // Final event request / booking flow — one EventRequest per event, with a
  // frozen snapshot per (re)submission. See backend/internal/models/event_request.go.
  getRequest: (id) => request(`/api/events/${id}/request`),
  updateRequest: (id, organizerComment) => request(`/api/events/${id}/request`, { method: 'PUT', body: { organizer_comment: organizerComment } }),
  submitRequest: (id) => request(`/api/events/${id}/request/submit`, { method: 'POST' }),
  cancelRequest: (id) => request(`/api/events/${id}/request/cancel`, { method: 'POST' }),
};
