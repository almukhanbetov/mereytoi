'use client';

import { getUserToken } from '@/lib/authApi';

const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8090';

function authHeaders() {
  const headers = { 'Content-Type': 'application/json' };
  const token = getUserToken();
  if (token) headers.Authorization = `Bearer ${token}`;
  return headers;
}

// GET /api/listings/feed — the catalog with paid ads («Реклама») placed by
// the server; the same filters as /api/listings, one page at a time.
export async function fetchFeedClient({ category, search, cursor, limit = 24 } = {}) {
  const params = new URLSearchParams({ limit: String(limit) });
  if (category && category !== 'all') params.set('category', category);
  if (search) params.set('search', search);
  if (cursor) params.set('cursor', cursor);
  const res = await fetch(`${API_URL}/api/listings/feed?${params}`);
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || `Request failed (${res.status})`);
  return { items: data.items || [], total: data.total || 0, nextCursor: data.next_cursor || null };
}

// impression | click | chat | call | whatsapp. Fire-and-forget: the server
// drops repeats, the owner's own views and inflation; a failure never
// bothers the visitor.
export function recordPromotionEvent(promotionId, kind) {
  if (!promotionId) return;
  try {
    fetch(`${API_URL}/api/promotions/events`, {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ promotion_id: promotionId, kind }),
      keepalive: true,
    }).catch(() => {});
  } catch {
    // ignore
  }
}

// A listing opened from its ad card: contacts on its page are attributed
// to that ad for the rest of the browser session.
const AD_OPEN_KEY = 'mereytoi_ad_opened';

export function rememberAdOpen(listingId, promotionId) {
  try {
    const map = JSON.parse(sessionStorage.getItem(AD_OPEN_KEY) || '{}');
    map[listingId] = promotionId;
    sessionStorage.setItem(AD_OPEN_KEY, JSON.stringify(map));
  } catch {
    // storage unavailable: attribution is simply skipped
  }
}

export function adPromotionFor(listingId) {
  try {
    const map = JSON.parse(sessionStorage.getItem(AD_OPEN_KEY) || '{}');
    return map[listingId] || null;
  } catch {
    return null;
  }
}

// GET /api/promotions/listings/:id — terms, price, status and statistics
// for the listing's owner/manager.
export async function fetchPromotionStatus(listingId) {
  const res = await fetch(`${API_URL}/api/promotions/listings/${listingId}`, { headers: authHeaders() });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || `Request failed (${res.status})`);
  return data;
}
