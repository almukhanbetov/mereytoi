import '../../models/listing.dart';
import '../../models/listing_menu.dart';

/// Resolved guest-count bounds for the stepper/slider: `max == null` means
/// there is genuinely no upper bound to enforce — never invented.
typedef GuestBounds = ({int min, int? max});

/// The menu's own `min_guests`/`max_guests` win when set (they're this
/// specific menu's order-size constraint); otherwise falls back to the
/// listing's own `min_guests`/`max_guests` (its pricing-tier range, `0`
/// meaning "not set" on that model). If neither says anything, the min
/// defaults to 1 guest and the max stays unbounded — deliberately *not*
/// porting the web calculator's own slider-only fallback
/// (`Math.max(minGuests * 4, 200)`, see RestaurantMenuCalculator.jsx),
/// since that's a UI slider-range convenience, not a real data constraint.
GuestBounds resolveGuestBounds({
  required ListingMenu? menu,
  required Listing listing,
}) {
  final min =
      menu?.minGuests ?? (listing.minGuests > 0 ? listing.minGuests : 1);
  final max =
      menu?.maxGuests ?? (listing.maxGuests > 0 ? listing.maxGuests : null);
  return (min: min, max: max);
}
