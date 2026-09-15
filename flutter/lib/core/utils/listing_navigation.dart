import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/restaurant/restaurant_category.dart';
import '../../models/listing.dart';
import '../../screens/restaurant/restaurant_detail_screen.dart';
import '../../screens/service_detail/service_detail_screen.dart';
import '../../state/categories_provider.dart';

/// Pushes the right detail screen for a listing: `RestaurantDetailScreen`
/// for the `venues` category, `ServiceDetailScreen` for everything else —
/// the one place this branch is made, so every list/grid/featured-strip
/// screen routes the same way.
///
/// `Listing.category` is only populated on the detail endpoint (GORM
/// `Preload`) — a listing from `GET /api/listings` (every call site this
/// is used from) always has a null `category`, only `categoryId`. So the
/// slug is resolved from the already-fetched `categoriesProvider` list
/// (every screen that renders a listings grid has already loaded it for
/// its own category filter/section) rather than requiring a second
/// network round-trip just to know which screen to push.
void pushListingDetail(BuildContext context, WidgetRef ref, Listing listing) {
  var slug = listing.category?.slug;
  if (slug == null) {
    final categories = ref.read(categoriesProvider).valueOrNull ?? const [];
    for (final category in categories) {
      if (category.id == listing.categoryId) {
        slug = category.slug;
        break;
      }
    }
  }
  debugPrint(
    '[QA] pushListingDetail: listing.id=${listing.id} categoryId=${listing.categoryId} '
    'resolvedSlug=$slug isRestaurant=${isRestaurantCategory(slug)}',
  );

  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => isRestaurantCategory(slug)
          ? RestaurantDetailScreen(listingId: listing.id)
          : ServiceDetailScreen(listingId: listing.id),
    ),
  );
}
