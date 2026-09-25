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
    this.myRole,
    this.priceType,
    this.provider,
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

  // ---- GET /api/users/me/listings only (myListingOut) — the caller's own
  // role on this listing: "admin" for a global admin, "owner"/"manager"
  // for a ListingManager row. Null on every other endpoint. ----
  final String? myRole;

  // ---- Этап 11 "Provider Marketplace" ----
  // priceType — fixed/from/per_hour/per_event/negotiable, empty string on
  // every listing predating this stage (backend's own omitempty).
  final String? priceType;
  // provider — the owning ListingManager(role=owner)'s Provider profile,
  // when one exists (see backend's attachProviderBriefs/loadListingProvider).
  // Null for every listing with no self-serve provider owner, i.e. every
  // admin-created restaurant/venue listing from before this stage.
  final ListingProviderBrief? provider;

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
      myRole: json['role'] as String?,
      priceType: json['price_type'] as String?,
      provider: json['provider'] is Map
          ? ListingProviderBrief.fromJson(
              Map<String, dynamic>.from(json['provider'] as Map),
            )
          : null,
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

/// The small, display-only slice of a Provider a catalog card/detail page
/// needs — mirrors backend/internal/handlers/listing_handler.go's own
/// `providerBrief` (catalog) shape; the detail endpoint actually sends the
/// full contact shape (phone/whatsapp/telegram included), so every field
/// here is nullable/optional to parse either shape without throwing. `id` —
/// Этап 11G: the provider's own public routing handle (never `user_id`,
/// which the backend deliberately never sends here — see
/// providerDetailOut's own doc comment), used to open ProviderProfileScreen
/// and to address POST /api/provider-chat/start.
class ListingProviderBrief {
  const ListingProviderBrief({
    required this.id,
    required this.displayName,
    this.city,
    this.avatarUrl,
    this.phone,
    this.whatsapp,
    this.telegram,
  });

  final int id;
  final String displayName;
  final String? city;
  final String? avatarUrl;
  final String? phone;
  final String? whatsapp;
  final String? telegram;

  factory ListingProviderBrief.fromJson(Map<String, dynamic> json) {
    return ListingProviderBrief(
      id: json['id'] as int? ?? 0,
      displayName: json['display_name'] as String? ?? '',
      city: json['city'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      phone: json['phone'] as String?,
      whatsapp: json['whatsapp'] as String?,
      telegram: json['telegram'] as String?,
    );
  }
}
