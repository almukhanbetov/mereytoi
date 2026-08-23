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

// Same values as the homepage stats block originally had hardcoded — used
// whenever the statistics API is unreachable so the section still renders.
export const DEFAULT_SITE_STATISTICS = {
  events_count: 250,
  happy_guests_count: 15000,
  years_experience: 8,
  cities_count: 5,
};

export async function fetchSiteStatistics() {
  const data = await apiGet("/api/site-statistics");
  return data ?? DEFAULT_SITE_STATISTICS;
}
