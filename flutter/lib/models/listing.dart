import '../state/locale_provider.dart';
import 'category.dart';

/// Mirrors backend/internal/models/listing.go's JSON shape exactly —
/// `GET /api/listings`, `GET /api/listings?category=<slug>`, `GET /api/listings/:id`.
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
    required this.isActive,
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
  final bool isActive;

  factory Listing.fromJson(Map<String, dynamic> json) {
    return Listing(
      id: json['id'] as int,
      categoryId: json['category_id'] as int? ?? 0,
      category: json['category'] is Map
          ? Category.fromJson(Map<String, dynamic>.from(json['category'] as Map))
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
      imageUrls: (json['image_urls'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  String name(AppLocale locale) => t(locale, ru: nameRu, kz: nameKz);
  String description(AppLocale locale) => t(locale, ru: descriptionRu, kz: descriptionKz);

  /// Per-person pricing (a venue priced per guest) vs a flat price — same
  /// rule the site uses (ServiceDetail.jsx: `min_guests>0 && max_guests>min_guests`).
  bool get isPerPerson => minGuests > 0 && maxGuests > minGuests;

  String? get coverImage => imageUrls.isNotEmpty ? imageUrls.first : null;
}
