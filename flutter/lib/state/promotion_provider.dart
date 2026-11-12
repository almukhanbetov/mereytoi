import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/listing.dart';
import '../models/promotion.dart';
import 'city_provider.dart';
import 'providers.dart';

/// The filters of one catalog result. The city comes from the global city
/// selector inside the provider, so it isn't part of the key.
class CatalogQuery {
  const CatalogQuery({this.categorySlug, this.search = ''});

  final String? categorySlug;
  final String search;

  @override
  bool operator ==(Object other) =>
      other is CatalogQuery &&
      other.categorySlug == categorySlug &&
      other.search == search;

  @override
  int get hashCode => Object.hash(categorySlug, search);
}

class CatalogFeedState {
  const CatalogFeedState({
    this.items = const [],
    this.total = 0,
    this.cursor,
    this.loading = true,
    this.loadingMore = false,
    this.error,
  });

  final List<Listing> items;
  final int total;
  final String? cursor;
  final bool loading;
  final bool loadingMore;
  final Object? error;

  bool get hasMore => cursor != null;

  CatalogFeedState copyWith({
    List<Listing>? items,
    int? total,
    String? cursor,
    bool clearCursor = false,
    bool? loading,
    bool? loadingMore,
    Object? error,
    bool clearError = false,
  }) => CatalogFeedState(
    items: items ?? this.items,
    total: total ?? this.total,
    cursor: clearCursor ? null : (cursor ?? this.cursor),
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    error: clearError ? null : (error ?? this.error),
  );
}

/// A paged catalog result with ads (GET /api/listings/feed). Pages are
/// appended in order; the server keeps ads in place across pages, so a
/// listing never repeats.
class CatalogFeedNotifier extends StateNotifier<CatalogFeedState> {
  CatalogFeedNotifier(this._ref, this.query, this._cityId)
    : super(const CatalogFeedState()) {
    reload();
  }

  final Ref _ref;
  final CatalogQuery query;
  final int? _cityId;
  int _generation = 0;

  static const pageSize = 20;

  Future<void> reload() async {
    final gen = ++_generation;
    state = const CatalogFeedState();
    try {
      await _ref.read(selectedCityIdProvider.notifier).ready;
      final page = await _ref
          .read(promotionServiceProvider)
          .fetchFeed(
            categorySlug: query.categorySlug,
            search: query.search,
            cityId: _cityId,
            limit: pageSize,
          );
      if (!mounted || gen != _generation) return;
      state = CatalogFeedState(
        items: page.items,
        total: page.total,
        cursor: page.nextCursor,
        loading: false,
      );
    } catch (e) {
      if (!mounted || gen != _generation) return;
      state = CatalogFeedState(loading: false, error: e);
    }
  }

  Future<void> loadMore() async {
    final cursor = state.cursor;
    if (cursor == null || state.loadingMore || state.loading) return;
    final gen = _generation;
    state = state.copyWith(loadingMore: true);
    try {
      final page = await _ref
          .read(promotionServiceProvider)
          .fetchFeed(
            categorySlug: query.categorySlug,
            search: query.search,
            cityId: _cityId,
            cursor: cursor,
            limit: pageSize,
          );
      if (!mounted || gen != _generation) return;
      final seen = {for (final l in state.items) l.id};
      state = state.copyWith(
        items: [...state.items, ...page.items.where((l) => seen.add(l.id))],
        total: page.total,
        cursor: page.nextCursor,
        clearCursor: page.nextCursor == null,
        loadingMore: false,
      );
    } catch (_) {
      // The next scroll to the end retries.
      if (mounted && gen == _generation) {
        state = state.copyWith(loadingMore: false);
      }
    }
  }
}

final catalogFeedProvider = StateNotifierProvider.autoDispose
    .family<CatalogFeedNotifier, CatalogFeedState, CatalogQuery>((ref, query) {
      final cityId = ref.watch(selectedCityIdProvider);
      return CatalogFeedNotifier(ref, query, cityId);
    });

/// Terms, price, status and statistics of promoting one listing.
final promotionStatusProvider = FutureProvider.autoDispose
    .family<PromotionStatus, int>((ref, listingId) {
      return ref.watch(promotionServiceProvider).fetchStatus(listingId);
    });

/// Reports ad events. Impressions go once per promotion per app session
/// (the server de-duplicates again per viewer); a listing opened from an ad
/// is remembered so the chat/call/WhatsApp taps on its page are attributed
/// to that ad. Failures never bother the person browsing.
class AdTracker {
  AdTracker(this._ref);

  final Ref _ref;
  final Set<int> _impressions = {};
  final Map<int, int> _openedFromAd = {};

  Future<void> _send(int promotionId, String kind) async {
    try {
      await _ref.read(promotionServiceProvider).recordEvent(promotionId, kind);
    } catch (_) {}
  }

  /// The ad card was actually on screen.
  void impression(int promotionId) {
    if (_impressions.add(promotionId)) _send(promotionId, 'impression');
  }

  /// The listing was opened from its ad card.
  void opened(Listing listing) {
    final id = listing.promotionId;
    if (!listing.promoted || id == null) return;
    _openedFromAd[listing.id] = id;
    _send(id, 'click');
  }

  /// chat | call | whatsapp, from the listing's own page.
  void contact(int listingId, String kind) {
    final id = _openedFromAd[listingId];
    if (id != null) _send(id, kind);
  }
}

final adTrackerProvider = Provider<AdTracker>((ref) => AdTracker(ref));
