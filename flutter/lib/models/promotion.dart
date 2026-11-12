import 'listing.dart';

/// Ad statistics of one promotion. Taps on chat/call/WhatsApp are contact
/// attempts, never confirmed orders.
class PromotionStats {
  const PromotionStats({
    this.impressions = 0,
    this.clicks = 0,
    this.chats = 0,
    this.calls = 0,
    this.whatsapp = 0,
  });

  final int impressions;
  final int clicks;
  final int chats;
  final int calls;
  final int whatsapp;

  factory PromotionStats.fromJson(Map<String, dynamic> json) => PromotionStats(
    impressions: json['impressions'] as int? ?? 0,
    clicks: json['clicks'] as int? ?? 0,
    chats: json['chats'] as int? ?? 0,
    calls: json['calls'] as int? ?? 0,
    whatsapp: json['whatsapp'] as int? ?? 0,
  );
}

/// One paid 7-day period.
class PromotionPeriod {
  const PromotionPeriod({
    required this.id,
    required this.status,
    required this.running,
    required this.channel,
    required this.startsAt,
    required this.endsAt,
    required this.stats,
  });

  final int id;

  /// active | refunded | revoked. An active period that's past its end is
  /// simply over ([running] is false).
  final String status;
  final bool running;
  final String channel;
  final DateTime startsAt;
  final DateTime endsAt;
  final PromotionStats stats;

  bool get refunded => status == 'refunded' || status == 'revoked';

  factory PromotionPeriod.fromJson(Map<String, dynamic> json) =>
      PromotionPeriod(
        id: json['id'] as int,
        status: json['status'] as String? ?? '',
        running: json['running'] as bool? ?? false,
        channel: json['channel'] as String? ?? '',
        startsAt: DateTime.parse(json['starts_at'] as String).toLocal(),
        endsAt: DateTime.parse(json['ends_at'] as String).toLocal(),
        stats: json['stats'] is Map
            ? PromotionStats.fromJson(
                Map<String, dynamic>.from(json['stats'] as Map),
              )
            : const PromotionStats(),
      );
}

/// Whether one payment channel can start a purchase, and why not.
class PromotionChannel {
  const PromotionChannel({
    required this.available,
    this.productId,
    this.reason,
  });

  final bool available;
  final String? productId;
  final String? reason;

  factory PromotionChannel.fromJson(Map<String, dynamic> json) =>
      PromotionChannel(
        available: json['available'] as bool? ?? false,
        productId: json['product_id'] as String?,
        reason: json['reason'] as String?,
      );
}

/// GET /api/promotions/listings/:id — terms, price and status of
/// promoting one listing.
class PromotionStatus {
  const PromotionStatus({
    required this.listingId,
    required this.durationDays,
    required this.autoRenew,
    required this.priceKzt,
    required this.channels,
    required this.canPurchase,
    required this.blockedReason,
    required this.running,
    required this.history,
  });

  final int listingId;
  final int durationDays;
  final bool autoRenew;
  final int priceKzt;
  final Map<String, PromotionChannel> channels;
  final bool canPurchase;

  /// promotions_disabled | price_not_set | not_owner | already_running |
  /// listing_hidden | provider_not_active | no_owner, or empty.
  final String blockedReason;
  final PromotionPeriod? running;
  final List<PromotionPeriod> history;

  PromotionChannel channel(String name) =>
      channels[name] ?? const PromotionChannel(available: false);

  factory PromotionStatus.fromJson(Map<String, dynamic> json) {
    final pkg = Map<String, dynamic>.from(json['package'] as Map? ?? const {});
    final channels = <String, PromotionChannel>{};
    (json['channels'] as Map? ?? const {}).forEach((k, v) {
      if (v is Map) {
        channels[k as String] = PromotionChannel.fromJson(
          Map<String, dynamic>.from(v),
        );
      }
    });
    return PromotionStatus(
      listingId: json['listing_id'] as int? ?? 0,
      durationDays: pkg['duration_days'] as int? ?? 7,
      autoRenew: pkg['auto_renew'] as bool? ?? false,
      priceKzt: pkg['price_kzt'] as int? ?? 0,
      channels: channels,
      canPurchase: json['can_purchase'] as bool? ?? false,
      blockedReason: json['blocked_reason'] as String? ?? '',
      running: json['running'] is Map
          ? PromotionPeriod.fromJson(
              Map<String, dynamic>.from(json['running'] as Map),
            )
          : null,
      history: (json['history'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => PromotionPeriod.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

/// POST /api/promotions/orders — binds a store purchase to one listing.
class PromotionOrder {
  const PromotionOrder({
    required this.id,
    required this.token,
    required this.productId,
  });

  final int id;

  /// Sent with the purchase (Google obfuscatedAccountId, Apple
  /// appAccountToken); the server only accepts a purchase quoting it.
  final String token;
  final String productId;

  factory PromotionOrder.fromJson(Map<String, dynamic> json) => PromotionOrder(
    id: json['id'] as int,
    token: json['token'] as String,
    productId: json['product_id'] as String,
  );
}

/// One page of GET /api/listings/feed.
class CatalogPage {
  const CatalogPage({
    required this.items,
    required this.total,
    required this.nextCursor,
  });

  final List<Listing> items;
  final int total;
  final String? nextCursor;
}
