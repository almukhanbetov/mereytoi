import '../state/locale_provider.dart';

/// Mirrors backend/internal/models/listing_menu.go's `ListingMenuItem` —
/// one dish inside a `ListingMenuSection`.
class ListingMenuItem {
  const ListingMenuItem({
    required this.id,
    required this.sectionId,
    required this.nameRu,
    required this.nameKz,
    this.descriptionRu = '',
    this.descriptionKz = '',
    this.quantityText = '',
    required this.sortOrder,
  });

  final int id;
  final int sectionId;
  final String nameRu;
  final String nameKz;
  final String descriptionRu;
  final String descriptionKz;

  /// Free-form display text ("200 г", "1 порция на гостя") — not a
  /// structured amount/unit pair, matching the backend's own field.
  final String quantityText;
  final int sortOrder;

  factory ListingMenuItem.fromJson(Map<String, dynamic> json) {
    return ListingMenuItem(
      id: json['id'] as int,
      sectionId: json['section_id'] as int? ?? 0,
      nameRu: json['name_ru'] as String? ?? '',
      nameKz: json['name_kz'] as String? ?? '',
      descriptionRu: json['description_ru'] as String? ?? '',
      descriptionKz: json['description_kz'] as String? ?? '',
      quantityText: json['quantity_text'] as String? ?? '',
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }

  String name(AppLocale locale) => t(locale, ru: nameRu, kz: nameKz);
  String description(AppLocale locale) =>
      t(locale, ru: descriptionRu, kz: descriptionKz);
}
