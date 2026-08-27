import '../core/network/api_client.dart';
import '../models/listing.dart';

/// Wraps GET /api/listings (optionally `?category=<slug>&search=<term>`,
/// same server-side filter the Go handler already supports) and
/// GET /api/listings/:id.
class ListingService {
  ListingService(this._client);

  final ApiClient _client;

  Future<List<Listing>> fetchListings({String? categorySlug, String? search}) async {
    final query = <String, dynamic>{};
    if (categorySlug != null && categorySlug.isNotEmpty) query['category'] = categorySlug;
    if (search != null && search.isNotEmpty) query['search'] = search;

    final json = await _client.getJson('/api/listings', query: query.isEmpty ? null : query);
    final raw = json['listings'] as List? ?? const [];
    return raw.map((e) => Listing.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<Listing> fetchById(int id) async {
    final json = await _client.getJson('/api/listings/$id');
    return Listing.fromJson(Map<String, dynamic>.from(json['listing'] as Map));
  }
}
