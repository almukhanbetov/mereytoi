import '../state/locale_provider.dart';
import 'listing_menu_extra.dart';
import 'listing_menu_section.dart';

/// Mirrors backend/internal/models/listing_menu.go's `ListingMenu` plus the
/// `sections`/`extras` arrays `menuOut` (listing_handler.go) nests onto it
/// wherever the full tree is loaded (`GET /api/listings/:id` and
/// `GET /api/listings/:id/menus`) — both default to empty so a plain
/// `ListingMenu` (e.g. from the admin CRUD response, which returns the bare
/// row) still parses.
class ListingMenu {
  const ListingMenu({
    required this.id,
    required this.listingId,
    this.hallId,
    required this.nameRu,
    required this.nameKz,
    this.descriptionRu = '',
    this.descriptionKz = '',
    required this.pricePerGuest,
    this.minGuests,
    this.maxGuests,
    required this.isActive,
    required this.sortOrder,
    this.validFrom,
    this.validUntil,
    this.sections = const [],
    this.extras = const [],
  });

  final int id;
  final int listingId;

  /// null = "available for any hall" — never assumed to mean "no hall
  /// exists"; see models.ListingMenu's own doc comment.
  final int? hallId;
  final String nameRu;
  final String nameKz;
  final String descriptionRu;
  final String descriptionKz;
  final int pricePerGuest;

  /// This menu's own order-size constraints — independent of
  /// `Listing.minGuests/maxGuests` (a pricing-tier range) and
  /// `ListingHall.capacity` (physical capacity). Pointers on the backend
  /// (0 is not a valid "no constraint" default), so nullable here too —
  /// never coerced to 0.
  final int? minGuests;
  final int? maxGuests;
  final bool isActive;
  final int sortOrder;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final List<ListingMenuSection> sections;
  final List<ListingMenuExtra> extras;

  factory ListingMenu.fromJson(Map<String, dynamic> json) {
    return ListingMenu(
      id: json['id'] as int,
      listingId: json['listing_id'] as int? ?? 0,
      hallId: json['hall_id'] as int?,
      nameRu: json['name_ru'] as String? ?? '',
      nameKz: json['name_kz'] as String? ?? '',
      descriptionRu: json['description_ru'] as String? ?? '',
      descriptionKz: json['description_kz'] as String? ?? '',
      pricePerGuest: json['price_per_guest'] as int? ?? 0,
      minGuests: json['min_guests'] as int?,
      maxGuests: json['max_guests'] as int?,
      isActive: json['is_active'] as bool? ?? true,
      sortOrder: json['sort_order'] as int? ?? 0,
      validFrom: json['valid_from'] != null
          ? DateTime.tryParse(json['valid_from'] as String)
          : null,
      validUntil: json['valid_until'] != null
          ? DateTime.tryParse(json['valid_until'] as String)
          : null,
      sections:
          (json['sections'] as List?)
              ?.map(
                (e) => ListingMenuSection.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ),
              )
              .toList() ??
          const [],
      extras:
          (json['extras'] as List?)
              ?.map(
                (e) => ListingMenuExtra.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ),
              )
              .toList() ??
          const [],
    );
  }

  String name(AppLocale locale) => t(locale, ru: nameRu, kz: nameKz);
  String description(AppLocale locale) =>
      t(locale, ru: descriptionRu, kz: descriptionKz);
}
