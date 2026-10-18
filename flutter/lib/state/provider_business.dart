import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'categories_provider.dart';
import 'listings_provider.dart';
import 'provider_provider.dart';

/// How many services the provider has — counted exactly like «Мои услуги»
/// (restaurants/venues have their own management flow and are excluded).
/// Null while loading or on error, so callers just hide the count.
final myServicesCountProvider = Provider<int?>((ref) {
  final listings = ref.watch(myListingsProvider).valueOrNull;
  final categories = ref.watch(categoriesProvider).valueOrNull;
  if (listings == null || categories == null) return null;
  final venueIds = {
    for (final c in categories)
      if (c.slug == 'venues') c.id,
  };
  return listings.where((l) => !venueIds.contains(l.categoryId)).length;
});

/// How many booking requests include the provider's services. Null while
/// loading or on error.
final myBookingsCountProvider = Provider<int?>((ref) {
  final bookings = ref.watch(providerBookingsProvider);
  // An error keeps the previous value — possibly another account's.
  if (bookings.hasError) return null;
  return bookings.valueOrNull?.length;
});
