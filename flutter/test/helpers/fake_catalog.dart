import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mereytoi_app/core/network/api_client.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/models/promotion.dart';
import 'package:mereytoi_app/services/promotion_service.dart';
import 'package:mereytoi_app/state/providers.dart';

/// Answers the catalog feed (GET /api/listings/feed) from in-memory lists
/// keyed by category slug (null = all), filtering by name like the server's
/// search, in one page. Ad events are accepted and ignored.
class FakeCatalogService extends PromotionService {
  FakeCatalogService(this.lists)
    : super(ApiClient.test(tokenProvider: () async => null));

  final Map<String?, Future<List<Listing>>> lists;
  final List<({String? category, String? search, int? cityId})> requests = [];
  final List<(int, String)> events = [];

  @override
  Future<CatalogPage> fetchFeed({
    String? categorySlug,
    String? search,
    int? cityId,
    String? cursor,
    int limit = 20,
  }) async {
    requests.add((category: categorySlug, search: search, cityId: cityId));
    final all = await (lists[categorySlug] ?? Future.value(const <Listing>[]));
    final term = (search ?? '').toLowerCase();
    final items = term.isEmpty
        ? all
        : all
              .where(
                (l) =>
                    l.nameRu.toLowerCase().contains(term) ||
                    l.nameKz.toLowerCase().contains(term),
              )
              .toList();
    return CatalogPage(items: items, total: items.length, nextCursor: null);
  }

  @override
  Future<void> recordEvent(int promotionId, String kind) async {
    events.add((promotionId, kind));
  }
}

Override fakeCatalog(Map<String?, Future<List<Listing>>> lists) =>
    promotionServiceProvider.overrideWithValue(FakeCatalogService(lists));
