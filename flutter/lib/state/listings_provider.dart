import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/listing.dart';
import '../models/listing_hall.dart';
import '../models/listing_menu.dart';
import 'providers.dart';

/// `categorySlug == null` fetches every active listing — same "all" default
/// the site's /services catalog uses before a filter chip is tapped.
final listingsProvider = FutureProvider.family<List<Listing>, String?>((
  ref,
  categorySlug,
) {
  return ref
      .watch(listingServiceProvider)
      .fetchListings(categorySlug: categorySlug);
});

final listingDetailProvider = FutureProvider.family<Listing, int>((ref, id) {
  return ref.watch(listingServiceProvider).fetchById(id);
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
