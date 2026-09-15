import '../state/locale_provider.dart';

/// Mirrors backend/internal/models/listing_menu.go's `ListingMenuExtra`
/// exactly. `type`/`unit` are free-form strings on the backend (not a DB
/// enum) — kept as plain `String` here too, no Dart enum invented for
/// them; the calculator that interprets `unit` ("percent"/"per_guest" vs a
/// flat amount) is Stage 2 scope, not this model.
class ListingMenuExtra {
  const ListingMenuExtra({
    required this.id,
    required this.menuId,
    required this.type,
    required this.titleRu,
    required this.titleKz,
    required this.price,
    this.unit = '',
    this.descriptionRu = '',
    this.descriptionKz = '',
    required this.sortOrder,
  });

  final int id;
  final int menuId;
  final String type;
  final String titleRu;
  final String titleKz;
  final int price;
  final String unit;
  final String descriptionRu;
  final String descriptionKz;
  final int sortOrder;

  factory ListingMenuExtra.fromJson(Map<String, dynamic> json) {
    return ListingMenuExtra(
      id: json['id'] as int,
      menuId: json['menu_id'] as int? ?? 0,
      type: json['type'] as String? ?? '',
      titleRu: json['title_ru'] as String? ?? '',
      titleKz: json['title_kz'] as String? ?? '',
      price: json['price'] as int? ?? 0,
      unit: json['unit'] as String? ?? '',
      descriptionRu: json['description_ru'] as String? ?? '',
      descriptionKz: json['description_kz'] as String? ?? '',
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }

  String title(AppLocale locale) => t(locale, ru: titleRu, kz: titleKz);
  String description(AppLocale locale) =>
      t(locale, ru: descriptionRu, kz: descriptionKz);
}
