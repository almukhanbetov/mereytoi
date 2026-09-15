import '../core/network/api_client.dart';
import '../models/listing.dart';
import '../models/listing_hall.dart';
import '../models/listing_menu.dart';

/// Wraps every public `/api/listings*` endpoint this app uses — restaurant
/// halls/menus included, since they're sub-resources of the same
/// `ListingHandler` on the backend (listing_handler.go), not a separate
/// domain: GET /api/listings (optionally `?category=<slug>&search=<term>`,
/// same server-side filter the Go handler already supports),
/// GET /api/listings/:id (full detail, halls/menus nested when present),
/// GET /api/listings/:id/halls, GET /api/listings/:id/menus. No admin-only
/// (mutating) restaurant endpoint is called here — this app is read-only
/// for halls/menus, same as it already is for listings/categories.
class ListingService {
  ListingService(this._client);

  final ApiClient _client;

  Future<List<Listing>> fetchListings({
    String? categorySlug,
    String? search,
  }) async {
    final query = <String, dynamic>{};
    if (categorySlug != null && categorySlug.isNotEmpty) {
      query['category'] = categorySlug;
    }
    if (search != null && search.isNotEmpty) query['search'] = search;

    final json = await _client.getJson(
      '/api/listings',
      query: query.isEmpty ? null : query,
    );
    final raw = json['listings'] as List? ?? const [];
    return raw
        .map((e) => Listing.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<Listing> fetchById(int id) async {
    final json = await _client.getJson('/api/listings/$id');
    return Listing.fromJson(Map<String, dynamic>.from(json['listing'] as Map));
  }

  /// GET /api/listings/:id/halls — active halls only (the handler's own
  /// filter, see listing_handler.go's `Halls`). Lighter than the full
  /// `GET /api/listings/:id`, for a hall-picker that doesn't also need the
  /// menu tree.
  Future<List<ListingHall>> fetchHalls(int listingId) async {
    final json = await _client.getJson('/api/listings/$listingId/halls');
    final raw = json['halls'] as List? ?? const [];
    return raw
        .map((e) => ListingHall.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// GET /api/listings/:id/menus — the full menu tree (sections/items/
  /// extras nested), the same 5-query-bound `loadListingTree` the detail
  /// endpoint uses. Useful on its own when a screen only needs to
  /// re-fetch/refresh menus without re-fetching the whole listing.
  Future<List<ListingMenu>> fetchMenus(int listingId) async {
    final json = await _client.getJson('/api/listings/$listingId/menus');
    final raw = json['menus'] as List? ?? const [];
    return raw
        .map((e) => ListingMenu.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}
