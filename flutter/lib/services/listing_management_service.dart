import '../core/network/api_client.dart';
import '../models/listing.dart';
import '../models/listing_hall.dart';
import '../models/listing_menu.dart';
import '../models/listing_menu_extra.dart';
import '../models/listing_menu_item.dart';
import '../models/listing_menu_section.dart';

/// Every write endpoint for a listing's own fields and its restaurant
/// structure (halls/menus/sections/items/extras) — all admin-only on the
/// backend (`middleware.RequireAdmin()`, see routes.go's `listings` admin
/// group), confirmed against `backend/internal/handlers/listing_handler.go`
/// and `listing_hall_handler.go`/`listing_menu_handler.go` directly before
/// writing this file. No endpoint here was invented — every one already
/// existed and is already used by the web admin panel
/// (`RestaurantHallsTab.jsx`/`RestaurantMenusTab.jsx`).
///
/// `Listing`/`ListingHall`/`ListingMenu` are all **full-replace** PUTs on
/// the backend (`Update` rebinds every field from the request body, not a
/// partial patch — verified directly in each handler) — every method here
/// that edits one of those three always sends every field, defaulting to
/// the row's own current value for anything the caller didn't explicitly
/// change, so an edit to (say) just the address can never silently blank
/// out image_urls or video_urls.
class ListingManagementService {
  ListingManagementService(this._client);

  final ApiClient _client;

  /// Every hall regardless of `is_active`, for the management UI — the
  /// public `GET /api/listings/:id/halls` (what `ListingService.fetchHalls`
  /// wraps) filters to active-only at the SQL level
  /// (`ListingHandler.Halls`), so an inactive hall would be permanently
  /// invisible to re-activate. `GET /api/listings/:id` embeds the same
  /// halls via `loadListingTree`, which has no such filter — this just
  /// reads that one field out of the full detail response instead of
  /// growing the shared `Listing` model with a field the public read-only
  /// screens never need.
  Future<List<ListingHall>> fetchAllHalls(int listingId) async {
    final json = await _client.getJson('/api/listings/$listingId');
    final listing = Map<String, dynamic>.from(json['listing'] as Map);
    final raw = listing['halls'] as List? ?? const [];
    return raw
        .map((e) => ListingHall.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  // ---------------------------------------------------------------------
  // Listing itself — "Основное" and "Адрес" tabs both write through this
  // one endpoint (PUT /api/listings/:id expects the *entire* listingInput
  // shape every time).
  // ---------------------------------------------------------------------

  Future<Listing> updateListing(
    Listing current, {
    String? nameRu,
    String? nameKz,
    String? descriptionRu,
    String? descriptionKz,
    String? city,
    String? phone,
    int? price,
    int? minGuests,
    int? maxGuests,
    String? address,
    double? latitude,
    double? longitude,
    String? placeId,
    int? capacity,
    // Этап 11 additions — same "own value overrides, else current" shape
    // as every other optional param above.
    List<String>? imageUrls,
    String? priceType,
    bool? isActive,
  }) async {
    final json = await _client.putJson('/api/listings/${current.id}', {
      'category_id': current.categoryId,
      'name_ru': nameRu ?? current.nameRu,
      'name_kz': nameKz ?? current.nameKz,
      'description_ru': descriptionRu ?? current.descriptionRu,
      'description_kz': descriptionKz ?? current.descriptionKz,
      'city': city ?? current.city,
      'phone': phone ?? current.phone,
      'price': price ?? current.price,
      'min_guests': minGuests ?? current.minGuests,
      'max_guests': maxGuests ?? current.maxGuests,
      'rating': current.rating,
      'emoji': current.emoji,
      'color_from': current.colorFrom,
      'color_to': current.colorTo,
      'image_urls': imageUrls ?? current.imageUrls,
      'video_urls': current.videoUrls,
      'address': address ?? current.address ?? '',
      'latitude': latitude ?? current.latitude,
      'longitude': longitude ?? current.longitude,
      'place_id': placeId ?? current.placeId,
      'capacity': capacity ?? current.capacity,
      'price_type': priceType ?? current.priceType ?? '',
      'is_active': isActive ?? current.isActive,
    });
    return Listing.fromJson(Map<String, dynamic>.from(json['listing'] as Map));
  }

  /// DELETE /api/listings/:id — Этап 11 "Мои услуги" delete. Same handler
  /// the admin catalog already used (listingHandler.Delete), now also
  /// reachable by an owner/manager via `RequireListingAccess` (see
  /// routes.go's `manage` group) rather than only a global admin.
  Future<void> deleteListing(int id) {
    return _client.deleteJson('/api/listings/$id');
  }

  // ---------------------------------------------------------------------
  // Halls — POST/PUT/DELETE /api/listings/:id/halls[/:hallId].
  // ---------------------------------------------------------------------

  Future<ListingHall> createHall(
    int listingId, {
    required String nameRu,
    required String nameKz,
    String descriptionRu = '',
    String descriptionKz = '',
    int capacity = 0,
    int price = 0,
    List<String> imageUrls = const [],
    bool isActive = true,
    int sortOrder = 0,
  }) async {
    final json = await _client.postJson('/api/listings/$listingId/halls', {
      'name_ru': nameRu,
      'name_kz': nameKz,
      'description_ru': descriptionRu,
      'description_kz': descriptionKz,
      'capacity': capacity,
      'price': price,
      'image_urls': imageUrls,
      'is_active': isActive,
      'sort_order': sortOrder,
    });
    return ListingHall.fromJson(Map<String, dynamic>.from(json['hall'] as Map));
  }

  Future<ListingHall> updateHall(
    int listingId,
    int hallId, {
    required String nameRu,
    required String nameKz,
    String descriptionRu = '',
    String descriptionKz = '',
    int capacity = 0,
    int price = 0,
    List<String> imageUrls = const [],
    bool isActive = true,
    int sortOrder = 0,
  }) async {
    final json = await _client
        .putJson('/api/listings/$listingId/halls/$hallId', {
          'name_ru': nameRu,
          'name_kz': nameKz,
          'description_ru': descriptionRu,
          'description_kz': descriptionKz,
          'capacity': capacity,
          'price': price,
          'image_urls': imageUrls,
          'is_active': isActive,
          'sort_order': sortOrder,
        });
    return ListingHall.fromJson(Map<String, dynamic>.from(json['hall'] as Map));
  }

  Future<void> deleteHall(int listingId, int hallId) {
    return _client.deleteJson('/api/listings/$listingId/halls/$hallId');
  }

  // ---------------------------------------------------------------------
  // Menus — POST/PUT/DELETE /api/listings/:id/menus[/:menuId].
  // ---------------------------------------------------------------------

  Future<ListingMenu> createMenu(
    int listingId, {
    int? hallId,
    required String nameRu,
    required String nameKz,
    String descriptionRu = '',
    String descriptionKz = '',
    int pricePerGuest = 0,
    int? minGuests,
    int? maxGuests,
    bool isActive = true,
    int sortOrder = 0,
    DateTime? validFrom,
    DateTime? validUntil,
  }) async {
    final json = await _client.postJson('/api/listings/$listingId/menus', {
      'hall_id': hallId,
      'name_ru': nameRu,
      'name_kz': nameKz,
      'description_ru': descriptionRu,
      'description_kz': descriptionKz,
      'price_per_guest': pricePerGuest,
      'min_guests': minGuests,
      'max_guests': maxGuests,
      'is_active': isActive,
      'sort_order': sortOrder,
      'valid_from': validFrom?.toIso8601String(),
      'valid_until': validUntil?.toIso8601String(),
    });
    return ListingMenu.fromJson(Map<String, dynamic>.from(json['menu'] as Map));
  }

  Future<ListingMenu> updateMenu(
    int listingId,
    int menuId, {
    int? hallId,
    required String nameRu,
    required String nameKz,
    String descriptionRu = '',
    String descriptionKz = '',
    int pricePerGuest = 0,
    int? minGuests,
    int? maxGuests,
    bool isActive = true,
    int sortOrder = 0,
    DateTime? validFrom,
    DateTime? validUntil,
  }) async {
    final json = await _client
        .putJson('/api/listings/$listingId/menus/$menuId', {
          'hall_id': hallId,
          'name_ru': nameRu,
          'name_kz': nameKz,
          'description_ru': descriptionRu,
          'description_kz': descriptionKz,
          'price_per_guest': pricePerGuest,
          'min_guests': minGuests,
          'max_guests': maxGuests,
          'is_active': isActive,
          'sort_order': sortOrder,
          'valid_from': validFrom?.toIso8601String(),
          'valid_until': validUntil?.toIso8601String(),
        });
    return ListingMenu.fromJson(Map<String, dynamic>.from(json['menu'] as Map));
  }

  Future<void> deleteMenu(int listingId, int menuId) {
    return _client.deleteJson('/api/listings/$listingId/menus/$menuId');
  }

  // ---------------------------------------------------------------------
  // Menu sections — backend `listingMenuSectionInput` only has
  // title_ru/title_kz/sort_order (no description, no is_active — never
  // invented here just because the brief's own wishlist mentioned them).
  // ---------------------------------------------------------------------

  Future<ListingMenuSection> createSection(
    int listingId,
    int menuId, {
    required String titleRu,
    required String titleKz,
    int sortOrder = 0,
  }) async {
    final json = await _client.postJson(
      '/api/listings/$listingId/menus/$menuId/sections',
      {'title_ru': titleRu, 'title_kz': titleKz, 'sort_order': sortOrder},
    );
    return ListingMenuSection.fromJson(
      Map<String, dynamic>.from(json['section'] as Map),
    );
  }

  Future<ListingMenuSection> updateSection(
    int listingId,
    int menuId,
    int sectionId, {
    required String titleRu,
    required String titleKz,
    int sortOrder = 0,
  }) async {
    final json = await _client.putJson(
      '/api/listings/$listingId/menus/$menuId/sections/$sectionId',
      {'title_ru': titleRu, 'title_kz': titleKz, 'sort_order': sortOrder},
    );
    return ListingMenuSection.fromJson(
      Map<String, dynamic>.from(json['section'] as Map),
    );
  }

  Future<void> deleteSection(int listingId, int menuId, int sectionId) {
    return _client.deleteJson(
      '/api/listings/$listingId/menus/$menuId/sections/$sectionId',
    );
  }

  // ---------------------------------------------------------------------
  // Menu items — no is_active field on the backend either.
  // ---------------------------------------------------------------------

  Future<ListingMenuItem> createItem(
    int listingId,
    int menuId,
    int sectionId, {
    required String nameRu,
    required String nameKz,
    String descriptionRu = '',
    String descriptionKz = '',
    String quantityText = '',
    int sortOrder = 0,
  }) async {
    final json = await _client.postJson(
      '/api/listings/$listingId/menus/$menuId/sections/$sectionId/items',
      {
        'name_ru': nameRu,
        'name_kz': nameKz,
        'description_ru': descriptionRu,
        'description_kz': descriptionKz,
        'quantity_text': quantityText,
        'sort_order': sortOrder,
      },
    );
    return ListingMenuItem.fromJson(
      Map<String, dynamic>.from(json['item'] as Map),
    );
  }

  Future<ListingMenuItem> updateItem(
    int listingId,
    int menuId,
    int sectionId,
    int itemId, {
    required String nameRu,
    required String nameKz,
    String descriptionRu = '',
    String descriptionKz = '',
    String quantityText = '',
    int sortOrder = 0,
  }) async {
    final json = await _client.putJson(
      '/api/listings/$listingId/menus/$menuId/sections/$sectionId/items/$itemId',
      {
        'name_ru': nameRu,
        'name_kz': nameKz,
        'description_ru': descriptionRu,
        'description_kz': descriptionKz,
        'quantity_text': quantityText,
        'sort_order': sortOrder,
      },
    );
    return ListingMenuItem.fromJson(
      Map<String, dynamic>.from(json['item'] as Map),
    );
  }

  Future<void> deleteItem(
    int listingId,
    int menuId,
    int sectionId,
    int itemId,
  ) {
    return _client.deleteJson(
      '/api/listings/$listingId/menus/$menuId/sections/$sectionId/items/$itemId',
    );
  }

  // ---------------------------------------------------------------------
  // Menu extras — no is_active field on the backend.
  // ---------------------------------------------------------------------

  Future<ListingMenuExtra> createExtra(
    int listingId,
    int menuId, {
    required String type,
    required String titleRu,
    required String titleKz,
    int price = 0,
    String unit = '',
    String descriptionRu = '',
    String descriptionKz = '',
    int sortOrder = 0,
  }) async {
    final json = await _client
        .postJson('/api/listings/$listingId/menus/$menuId/extras', {
          'type': type,
          'title_ru': titleRu,
          'title_kz': titleKz,
          'price': price,
          'unit': unit,
          'description_ru': descriptionRu,
          'description_kz': descriptionKz,
          'sort_order': sortOrder,
        });
    return ListingMenuExtra.fromJson(
      Map<String, dynamic>.from(json['extra'] as Map),
    );
  }

  Future<ListingMenuExtra> updateExtra(
    int listingId,
    int menuId,
    int extraId, {
    required String type,
    required String titleRu,
    required String titleKz,
    int price = 0,
    String unit = '',
    String descriptionRu = '',
    String descriptionKz = '',
    int sortOrder = 0,
  }) async {
    final json = await _client
        .putJson('/api/listings/$listingId/menus/$menuId/extras/$extraId', {
          'type': type,
          'title_ru': titleRu,
          'title_kz': titleKz,
          'price': price,
          'unit': unit,
          'description_ru': descriptionRu,
          'description_kz': descriptionKz,
          'sort_order': sortOrder,
        });
    return ListingMenuExtra.fromJson(
      Map<String, dynamic>.from(json['extra'] as Map),
    );
  }

  Future<void> deleteExtra(int listingId, int menuId, int extraId) {
    return _client.deleteJson(
      '/api/listings/$listingId/menus/$menuId/extras/$extraId',
    );
  }
}
