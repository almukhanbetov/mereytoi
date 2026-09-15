import '../state/locale_provider.dart';
import 'category.dart';

/// Mirrors backend/internal/models/listing.go's JSON shape, plus the two
/// admin-facing wrapper shapes the same field set is embedded in:
///   - `GET /api/listings` (+ `?category=`/`?search=`) → `listingOut`:
///     Listing + `hall_count`/`menu_count`/`min_menu_price_per_guest`
///     (all `omitempty`) — no nested `halls`/`menus`.
///   - `GET /api/listings/:id` → `listingDetailOut`: Listing +
///     `halls`/`menus` (both `omitempty`), no aggregate counts.
/// A plain `Listing` never carries both at once in practice — this model
/// just keeps every field nullable/optional so parsing either shape (or a
/// bare `models.Listing`, e.g. inside a Booking/EventCandidate echo) never
/// throws, matching how loosely-shaped the actual API already is.
///
/// `category` is only populated on the detail endpoint (GORM `Preload`);
/// the list endpoint omits it (`omitempty`), so it's nullable here too.
class Listing {
  const Listing({
    required this.id,
    required this.categoryId,
    this.category,
    required this.nameRu,
    required this.nameKz,
    required this.descriptionRu,
    required this.descriptionKz,
    required this.city,
    required this.phone,
    required this.price,
    required this.minGuests,
    required this.maxGuests,
    required this.rating,
    required this.emoji,
    required this.colorFrom,
    required this.colorTo,
    required this.imageUrls,
    this.videoUrls = const [],
    required this.isActive,
    this.address,
    this.latitude,
    this.longitude,
    this.placeId,
    this.capacity = 0,
    this.hallCount,
    this.menuCount,
    this.minMenuPricePerGuest,
  });

  final int id;
  final int categoryId;
  final Category? category;
  final String nameRu;
  final String nameKz;
  final String descriptionRu;
  final String descriptionKz;
  final String city;
  final String phone;
  final int price;
  final int minGuests;
  final int maxGuests;
  final double rating;
  final String emoji;
  final String colorFrom;
  final String colorTo;
  final List<String> imageUrls;
  final List<String> videoUrls;
  final bool isActive;

  // ---- Restaurant/venue location fields (Listing.Address/Latitude/
  // Longitude/PlaceID/Capacity — all additive + omitempty on the backend,
  // so a non-restaurant listing simply never has them). Latitude/Longitude
  // are `*float64` on the Go side: either both a real JSON number or both
  // entirely absent, never a string — see hasCoords below, no `!` used on
  // either. ----
  final String? address;
  final double? latitude;
  final double? longitude;
  final String? placeId;
  final int capacity;

  // ---- List-endpoint-only aggregates (listingOut). Both null on a
  // Listing parsed from the detail endpoint, and null for a listing with
  // zero halls/menus (the handler's own `omitempty`, not "no data"). ----
  final int? hallCount;
  final int? menuCount;
  final int? minMenuPricePerGuest;

  factory Listing.fromJson(Map<String, dynamic> json) {
    return Listing(
      id: json['id'] as int,
      categoryId: json['category_id'] as int? ?? 0,
      category: json['category'] is Map
          ? Category.fromJson(
              Map<String, dynamic>.from(json['category'] as Map),
            )
          : null,
      nameRu: json['name_ru'] as String? ?? '',
      nameKz: json['name_kz'] as String? ?? '',
      descriptionRu: json['description_ru'] as String? ?? '',
      descriptionKz: json['description_kz'] as String? ?? '',
      city: json['city'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      price: json['price'] as int? ?? 0,
      minGuests: json['min_guests'] as int? ?? 0,
      maxGuests: json['max_guests'] as int? ?? 0,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      emoji: json['emoji'] as String? ?? '',
      colorFrom: json['color_from'] as String? ?? '',
      colorTo: json['color_to'] as String? ?? '',
      imageUrls:
          (json['image_urls'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      videoUrls:
          (json['video_urls'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      isActive: json['is_active'] as bool? ?? true,
      address: json['address'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      placeId: json['place_id'] as String?,
      capacity: json['capacity'] as int? ?? 0,
      hallCount: json['hall_count'] as int?,
      menuCount: json['menu_count'] as int?,
      minMenuPricePerGuest: json['min_menu_price_per_guest'] as int?,
    );
  }

  String name(AppLocale locale) => t(locale, ru: nameRu, kz: nameKz);
  String description(AppLocale locale) =>
      t(locale, ru: descriptionRu, kz: descriptionKz);

  /// Per-person pricing (a venue priced per guest) vs a flat price — same
  /// rule the site uses (ServiceDetail.jsx: `min_guests>0 && max_guests>min_guests`).
  bool get isPerPerson => minGuests > 0 && maxGuests > minGuests;

  String? get coverImage => imageUrls.isNotEmpty ? imageUrls.first : null;

  /// Same rule as frontend/src/components/services/RestaurantLocation.jsx's
  /// `hasCoords` — both present, both real numbers. Never assumed from
  /// `address`/`placeId` alone (either can exist without the other).
  bool get hasCoords => latitude != null && longitude != null;
}
