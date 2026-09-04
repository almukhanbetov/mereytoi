'use client';

// A tiny client-safe read of the public catalog — the server-side helpers in
// lib/api.js use a server-only env var (BACKEND_API_URL) and can't run in a
// 'use client' component, so the event workspace (which needs the category
// list to build its "N из M категорий" progress view) gets its own.
const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8090';

export async function fetchCategoriesClient() {
  const res = await fetch(`${API_URL}/api/categories`);
  const data = await res.json().catch(() => ({}));
  return data.categories || [];
}
