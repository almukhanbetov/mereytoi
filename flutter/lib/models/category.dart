import '../state/locale_provider.dart';

/// Mirrors backend/internal/models/category.go's JSON shape exactly —
/// GET /api/categories and GET /api/categories/:slug.
class Category {
  const Category({
    required this.id,
    required this.slug,
    required this.nameRu,
    required this.nameKz,
    required this.position,
    this.imageUrl,
  });

  final int id;
  final String slug;
  final String nameRu;
  final String nameKz;
  final int position;
  final String? imageUrl;

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] as int,
      slug: json['slug'] as String? ?? '',
      nameRu: json['name_ru'] as String? ?? '',
      nameKz: json['name_kz'] as String? ?? '',
      position: json['position'] as int? ?? 0,
      imageUrl: json['image_url'] as String?,
    );
  }

  String name(AppLocale locale) => t(locale, ru: nameRu, kz: nameKz);
}
