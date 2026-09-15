import '../state/locale_provider.dart';
import 'listing_menu_item.dart';

/// Mirrors backend/internal/models/listing_menu.go's `ListingMenuSection`
/// plus the `items` array the handler's `menuSectionOut` wrapper nests
/// under it (`listing_handler.go`'s `loadListingTree`) — the plain
/// `ListingMenuSection` alone (e.g. from the admin CRUD response) never
/// carries `items`, so this defaults to an empty list rather than requiring
/// the key.
class ListingMenuSection {
  const ListingMenuSection({
    required this.id,
    required this.menuId,
    required this.titleRu,
    required this.titleKz,
    required this.sortOrder,
    this.items = const [],
  });

  final int id;
  final int menuId;
  final String titleRu;
  final String titleKz;
  final int sortOrder;
  final List<ListingMenuItem> items;

  factory ListingMenuSection.fromJson(Map<String, dynamic> json) {
    return ListingMenuSection(
      id: json['id'] as int,
      menuId: json['menu_id'] as int? ?? 0,
      titleRu: json['title_ru'] as String? ?? '',
      titleKz: json['title_kz'] as String? ?? '',
      sortOrder: json['sort_order'] as int? ?? 0,
      items:
          (json['items'] as List?)
              ?.map(
                (e) => ListingMenuItem.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ),
              )
              .toList() ??
          const [],
    );
  }

  String title(AppLocale locale) => t(locale, ru: titleRu, kz: titleKz);
}
