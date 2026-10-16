import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/listing.dart';
import '../models/listing_hall.dart';
import '../models/listing_menu.dart';
import 'city_provider.dart';
import 'providers.dart';

/// `categorySlug == null` fetches every active listing — same "all" default
/// the site's /services catalog uses before a filter chip is tapped.
///
/// Also scoped to the globally selected city ([selectedCityIdProvider]):
/// the family key stays the category slug (so every existing
/// `listingsProvider(slug)` call site/override is unchanged), and a city
/// change refetches exactly the listing lists currently watched — nothing
/// else on screen rebuilds. Waits for the saved city to be restored first,
/// so app start doesn't fetch "all cities" and then refetch.
final listingsProvider = FutureProvider.family<List<Listing>, String?>((
  ref,
  categorySlug,
) async {
  await ref.watch(selectedCityIdProvider.notifier).ready;
  final cityId = ref.watch(selectedCityIdProvider);
  return ref
      .watch(listingServiceProvider)
      .fetchListings(categorySlug: categorySlug, cityId: cityId);
});

final listingDetailProvider = FutureProvider.family<Listing, int>((ref, id) {
  return ref.watch(listingServiceProvider).fetchById(id);
});

/// "Мои рестораны" (brief Этап 6) — every listing the current user may
/// manage: all of them for a global admin, only the ones they're an
/// owner/manager of otherwise. See [ListingService.fetchMyListings].
final myListingsProvider = FutureProvider<List<Listing>>((ref) {
  return ref.watch(listingServiceProvider).fetchMyListings();
});

/// Stage 2 (restaurant halls/menus UI) scaffolding — not consumed by any
/// screen yet. `listingDetailProvider` above already returns halls/menus
/// nested (GET /api/listings/:id), so a restaurant detail screen may not
/// even need these; they exist for a screen that wants to refresh just the
/// hall list or just the menu tree without re-fetching the whole listing.
final listingHallsProvider = FutureProvider.family<List<ListingHall>, int>((
  ref,
  listingId,
) {
  return ref.watch(listingServiceProvider).fetchHalls(listingId);
});

final listingMenusProvider = FutureProvider.family<List<ListingMenu>, int>((
  ref,
  listingId,
) {
  return ref.watch(listingServiceProvider).fetchMenus(listingId);
});
