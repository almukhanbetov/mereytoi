// The backend has no explicit "is this category a restaurant/venue"
// flag — per the architecture audit, a restaurant is just a Listing under
// the category seeded with this exact slug (see backend/internal/seed/seed.go:
// `Slug: "venues", NameRu: "Рестораны и локации"`). This is a slug-based
// heuristic, matching how the backend itself already scopes the
// selected-candidate-demotion logic — not a real "category type" field,
// which doesn't exist anywhere in this codebase yet.
export const RESTAURANT_CATEGORY_SLUG = 'venues';

export function isRestaurantCategory(category) {
  return category?.slug === RESTAURANT_CATEGORY_SLUG;
}
