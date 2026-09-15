/// Mirrors frontend/src/lib/restaurantCategory.js exactly: the one category
/// slug that gets the restaurant-specific detail screen instead of the
/// generic one.
const restaurantCategorySlug = 'venues';

bool isRestaurantCategory(String? categorySlug) =>
    categorySlug == restaurantCategorySlug;
