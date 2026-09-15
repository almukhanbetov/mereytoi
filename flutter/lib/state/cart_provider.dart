import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/cart_storage.dart';
import '../models/cart_item.dart';

/// Same semantics as the site's cart context
/// (frontend/src/context/AppProviders.jsx): adding an item that's already
/// in the cart *replaces* that entry rather than stacking a quantity —
/// there's no generic "quantity" concept server-side, only per-person
/// `guests` for listings priced that way. Identity is [CartItem.key] —
/// `(listingId, hallId, menuId)` — not just `listingId` (Stage 3): two
/// different halls/menus of the same restaurant listing are two different
/// entries, exactly like the site's own
/// `${listingId}:${hallId || ''}:${menuId || ''}` cart key.
///
/// State itself stays purely local/in-memory (independent of the network —
/// nothing here talks to the API), but is now also mirrored to
/// `CartStorage` (shared_preferences) on every change, and restored once at
/// startup, so the cart survives an app restart — the same
/// restore-on-start shape `AuthNotifier` already uses for its own session.
class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier(this._storage) : super(const []) {
    _readyCompleter = _restore();
  }

  final CartStorage _storage;
  late final Future<void> _readyCompleter;

  /// Resolves once the initial restore-from-storage attempt has finished
  /// (successfully or not) — lets a test await past hydration
  /// deterministically instead of guessing at a delay.
  @visibleForTesting
  Future<void> get ready => _readyCompleter;

  Future<void>? _lastPersist;

  /// Resolves once the most recently started write has actually reached
  /// storage — same reasoning as [ready], for the write side.
  @visibleForTesting
  Future<void> get debugPersisted => _lastPersist ?? Future.value();

  Future<void> _restore() async {
    final saved = await _storage.read();
    if (!mounted) return;
    // Never overwrites a cart that already has items by the time this
    // resolves (e.g. the user added something before storage finished
    // reading) — and an empty saved cart is simply a no-op either way.
    if (saved.isNotEmpty && state.isEmpty) {
      state = saved;
    }
  }

  void addItem(CartItem item) {
    state = [...state.where((i) => i.key != item.key), item];
    _persist();
  }

  void removeItem(CartItemKey key) {
    state = state.where((i) => i.key != key).toList();
    _persist();
  }

  void clear() {
    state = const [];
    _persist();
  }

  /// Ordinary-service convenience: true if *any* variant of this listing is
  /// in the cart. An ordinary service only ever has one variant
  /// (`hallId`/`menuId` both null), so this is exact for that case.
  bool contains(int listingId) => state.any((i) => i.listingId == listingId);

  /// Exact variant check — used by the restaurant CTA to decide whether
  /// adding this exact hall/menu combination is a fresh add ("Добавлено в
  /// корзину") or an update to what's already there ("Корзина обновлена").
  bool containsKey(CartItemKey key) => state.any((i) => i.key == key);

  void _persist() {
    _lastPersist = _storage.write(state);
  }
}

final cartProvider = StateNotifierProvider<CartNotifier, List<CartItem>>((ref) {
  return CartNotifier(CartStorage.instance);
});

/// Each `CartItem` is already one distinct variant (see [CartItem.key]), so
/// this is exactly the "count of variants" badge the bottom nav wants —
/// an ordinary service plus two halls/menus of the same restaurant is 3.
final cartCountProvider = Provider<int>(
  (ref) => ref.watch(cartProvider).length,
);

final cartTotalProvider = Provider<int>((ref) {
  return ref
      .watch(cartProvider)
      .fold<int>(0, (sum, item) => sum + item.totalPrice);
});
