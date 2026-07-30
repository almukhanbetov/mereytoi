const API_URL = process.env.BACKEND_API_URL || "http://localhost:8090";

async function apiGet(path) {
  try {
    const res = await fetch(`${API_URL}${path}`, { cache: "no-store" });
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  }
}

export async function fetchCategories() {
  const data = await apiGet("/api/categories");
  return data?.categories ?? [];
}

export async function fetchListings() {
  const data = await apiGet("/api/listings");
  return data?.listings ?? [];
}

export async function fetchListingsByCategory(slug) {
  const data = await apiGet(`/api/listings?category=${encodeURIComponent(slug)}`);
  return data?.listings ?? [];
}

export async function fetchListing(id) {
  const data = await apiGet(`/api/listings/${id}`);
  return data?.listing ?? null;
}
