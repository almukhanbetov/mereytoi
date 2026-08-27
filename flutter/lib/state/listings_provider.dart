import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/listing.dart';
import 'providers.dart';

/// `categorySlug == null` fetches every active listing — same "all" default
/// the site's /services catalog uses before a filter chip is tapped.
final listingsProvider = FutureProvider.family<List<Listing>, String?>((ref, categorySlug) {
  return ref.watch(listingServiceProvider).fetchListings(categorySlug: categorySlug);
});

final listingDetailProvider = FutureProvider.family<Listing, int>((ref, id) {
  return ref.watch(listingServiceProvider).fetchById(id);
});
