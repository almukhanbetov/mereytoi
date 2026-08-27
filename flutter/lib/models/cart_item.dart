import 'listing.dart';

/// A line in the local booking cart — same shape the site keeps in
/// localStorage (frontend/src/context/AppProviders.jsx's cart `items`)
/// and the same shape POST /api/bookings expects per item
/// (backend/internal/handlers/booking_handler.go's `bookingItemInput`).
class CartItem {
  const CartItem({
    required this.listingId,
    required this.name,
    required this.category,
    required this.image,
    required this.unitPrice,
    required this.guests,
    required this.totalPrice,
  });

  final int listingId;
  final String name;
  final String category;
  final String? image;
  final int unitPrice;
  final int guests; // 0 for flat-priced listings, matching the site's convention
  final int totalPrice;

  /// Builds a cart entry the same way the site's ServiceDetail.jsx does:
  /// per-person listings multiply guests × price, otherwise it's the flat
  /// listing price. `name`/`categoryLabel` are passed in already resolved
  /// to the current locale, same as the site resolves them at add-time.
  factory CartItem.fromListing(Listing listing, {required String name, required String categoryLabel, int guests = 1}) {
    final isPerPerson = listing.isPerPerson;
    final effectiveGuests = isPerPerson ? guests : 0;
    final total = isPerPerson ? guests * listing.price : listing.price;
    return CartItem(
      listingId: listing.id,
      name: name,
      category: categoryLabel,
      image: listing.coverImage,
      unitPrice: listing.price,
      guests: effectiveGuests,
      totalPrice: total,
    );
  }

  Map<String, dynamic> toBookingItemJson() => {
        'listing_id': listingId,
        'name': name,
        'category': category,
        'guests': guests,
        'unit_price': unitPrice,
        'total_price': totalPrice,
      };
}
