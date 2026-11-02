import '../../models/listing.dart';

/// Pure-Dart port of frontend/src/components/services/RestaurantLocation.jsx's
/// `directionsUrl` logic — same priority, same URLs, not reinterpreted:
/// Google Place ID → saved coordinates → free-text address/city. Returns
/// `null` when there's genuinely nothing to route to (`!addressText &&
/// !hasCoords`), the same case the web component renders nothing for.
///
/// Deliberately just a URL string — opening it is the caller's job via
/// `url_launcher` (`LaunchMode.externalApplication`), the same pattern
/// `lib/core/utils/whatsapp.dart` already uses. Needs no Maps SDK or API
/// key (the embedded map is `widgets/restaurant/venue_map.dart`).
String? restaurantDirectionsUrl(Listing listing) {
  final hasCoords = listing.hasCoords;
  final addressText = (listing.address != null && listing.address!.isNotEmpty)
      ? listing.address!
      : listing.city;

  if (addressText.isEmpty && !hasCoords) return null;

  final placeId = listing.placeId;
  if (placeId != null && placeId.isNotEmpty) {
    final destination = Uri.encodeComponent(addressText);
    final encodedPlaceId = Uri.encodeComponent(placeId);
    return 'https://www.google.com/maps/dir/?api=1&destination=$destination&destination_place_id=$encodedPlaceId';
  }

  if (hasCoords) {
    return 'https://www.google.com/maps/dir/?api=1&destination=${listing.latitude},${listing.longitude}';
  }

  return 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(addressText)}';
}

/// Whether the venue's own location is actually known: saved coordinates, a
/// Google Place ID, or a street address. A bare `city` is not a location —
/// a map or route built from it shows the whole city, not the venue, so
/// callers show «Местоположение пока не указано» instead of a map link.
bool hasVenueLocation(Listing listing) =>
    listing.hasCoords ||
    (listing.placeId?.isNotEmpty ?? false) ||
    (listing.address?.isNotEmpty ?? false);

/// "Show on map" link — the mobile counterpart of the web shortlist's
/// «Посмотреть на карте» (google.com/maps?q=lat,lng). Same priority as
/// [restaurantDirectionsUrl]: Place ID → coordinates → street address.
/// `null` when [hasVenueLocation] is false.
String? restaurantMapUrl(Listing listing) {
  if (!hasVenueLocation(listing)) return null;
  final address = listing.address ?? '';
  final placeId = listing.placeId;
  final query = listing.hasCoords
      ? '${listing.latitude},${listing.longitude}'
      : Uri.encodeComponent(address.isNotEmpty ? address : listing.city);
  if (placeId != null && placeId.isNotEmpty) {
    return 'https://www.google.com/maps/search/?api=1&query=$query'
        '&query_place_id=${Uri.encodeComponent(placeId)}';
  }
  return 'https://www.google.com/maps/search/?api=1&query=$query';
}
