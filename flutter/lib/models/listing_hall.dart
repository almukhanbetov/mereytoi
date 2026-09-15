import '../state/locale_provider.dart';

/// Mirrors backend/internal/models/listing_hall.go's JSON shape exactly —
/// returned nested in `GET /api/listings/:id`'s `halls` array, and as the
/// plain array from `GET /api/listings/:id/halls` (active halls only).
class ListingHall {
  const ListingHall({
    required this.id,
    required this.listingId,
    required this.nameRu,
    required this.nameKz,
    this.descriptionRu = '',
    this.descriptionKz = '',
    required this.capacity,
    required this.price,
    required this.imageUrls,
    required this.isActive,
    required this.sortOrder,
  });

  final int id;
  final int listingId;
  final String nameRu;
  final String nameKz;
  final String descriptionRu;
  final String descriptionKz;
  final int capacity;

  /// 0 means "inherit the parent Listing's own price" — see
  /// models.ListingHall's own doc comment; never resolved here, a caller
  /// that needs the effective price picks this when non-zero, else the
  /// Listing's own `price`.
  final int price;
  final List<String> imageUrls;
  final bool isActive;
  final int sortOrder;

  factory ListingHall.fromJson(Map<String, dynamic> json) {
    return ListingHall(
      id: json['id'] as int,
      listingId: json['listing_id'] as int? ?? 0,
      nameRu: json['name_ru'] as String? ?? '',
      nameKz: json['name_kz'] as String? ?? '',
      descriptionRu: json['description_ru'] as String? ?? '',
      descriptionKz: json['description_kz'] as String? ?? '',
      capacity: json['capacity'] as int? ?? 0,
      price: json['price'] as int? ?? 0,
      imageUrls:
          (json['image_urls'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      isActive: json['is_active'] as bool? ?? true,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }

  String name(AppLocale locale) => t(locale, ru: nameRu, kz: nameKz);
  String description(AppLocale locale) =>
      t(locale, ru: descriptionRu, kz: descriptionKz);
  String? get coverImage => imageUrls.isNotEmpty ? imageUrls.first : null;
}
