import '../../models/listing.dart';

/// Pure-Dart port of frontend/src/components/services/RestaurantLocation.jsx's
/// `directionsUrl` logic — same priority, same URLs, not reinterpreted:
/// Google Place ID → saved coordinates → free-text address/city. Returns
/// `null` when there's genuinely nothing to route to (`!addressText &&
/// !hasCoords`), the same case the web component renders nothing for.
///
/// Deliberately just a URL string — opening it is the caller's job via
/// `url_launcher` (`LaunchMode.externalApplication`), the same pattern
/// `lib/core/utils/whatsapp.dart` already uses. No Google Maps SDK, no
/// API key, matching the brief's explicit constraint.
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
