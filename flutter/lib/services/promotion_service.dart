import '../core/network/api_client.dart';
import '../models/listing.dart';
import '../models/promotion.dart';

/// Paid promotion API (backend handlers/promotion_handler.go). Every
/// purchase is verified by the server with the store; nothing here can
/// activate a promotion by itself.
class PromotionService {
  PromotionService(this._client);

  final ApiClient _client;

  /// GET /api/listings/feed — the catalog with ads, one page at a time.
  /// The same filters as GET /api/listings; pass the previous page's
  /// cursor for the next one.
  Future<CatalogPage> fetchFeed({
    String? categorySlug,
    String? search,
    int? cityId,
    String? cursor,
    int limit = 20,
  }) async {
    final query = <String, dynamic>{'limit': limit};
    if (categorySlug != null && categorySlug.isNotEmpty) {
      query['category'] = categorySlug;
    }
    if (search != null && search.isNotEmpty) query['search'] = search;
    if (cityId != null) query['city_id'] = cityId;
    if (cursor != null) query['cursor'] = cursor;
    final json = await _client.getJson('/api/listings/feed', query: query);
    final items = (json['items'] as List? ?? const [])
        .map((e) => Listing.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return CatalogPage(
      items: items,
      total: json['total'] as int? ?? items.length,
      nextCursor: json['next_cursor'] as String?,
    );
  }

  Future<PromotionStatus> fetchStatus(int listingId) async {
    final json = await _client.getJson('/api/promotions/listings/$listingId');
    return PromotionStatus.fromJson(json);
  }

  Future<PromotionOrder> createOrder(int listingId, String channel) async {
    final json = await _client.postJson('/api/promotions/orders', {
      'listing_id': listingId,
      'channel': channel,
    });
    return PromotionOrder.fromJson(
      Map<String, dynamic>.from(json['order'] as Map),
    );
  }

  /// Returns true once the server has verified the payment and the
  /// promotion exists; false while the store still reports it pending.
  Future<bool> confirmGoogle(int orderId, String purchaseToken) async {
    final json = await _client.postJson('/api/promotions/purchases/google', {
      'order_id': orderId,
      'purchase_token': purchaseToken,
    });
    return json['promotion'] != null;
  }

  Future<bool> confirmApple(int orderId, String signedTransaction) async {
    final json = await _client.postJson('/api/promotions/purchases/apple', {
      'order_id': orderId,
      'signed_transaction': signedTransaction,
    });
    return json['promotion'] != null;
  }

  /// impression | click | chat | call | whatsapp. The server decides what
  /// counts (repeats, own views and inflation are dropped there).
  Future<void> recordEvent(int promotionId, String kind) async {
    await _client.postJson('/api/promotions/events', {
      'promotion_id': promotionId,
      'kind': kind,
    });
  }
}
