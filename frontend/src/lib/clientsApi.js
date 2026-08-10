'use client';

const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8090';

export async function fetchClients() {
  const res = await fetch(`${API_URL}/api/clients`, { cache: 'no-store' });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) return [];
  return data.clients || [];
}
