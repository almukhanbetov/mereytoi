import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/cart_item.dart';

/// Same semantics as the site's cart context
/// (frontend/src/context/AppProviders.jsx): adding a listing that's already
/// in the cart *replaces* that entry rather than stacking a quantity —
/// there's no generic "quantity" concept server-side, only per-person
/// `guests` for listings priced that way. Kept in memory only: purely
/// local state, independent of the network, so a temporary API error can
/// never wipe it out (nothing here talks to the API at all).
class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier() : super(const []);

  void addItem(CartItem item) {
    state = [...state.where((i) => i.listingId != item.listingId), item];
  }

  void removeItem(int listingId) {
    state = state.where((i) => i.listingId != listingId).toList();
  }

  void clear() {
    state = const [];
  }

  bool contains(int listingId) => state.any((i) => i.listingId == listingId);
}

final cartProvider = StateNotifierProvider<CartNotifier, List<CartItem>>((ref) => CartNotifier());

final cartCountProvider = Provider<int>((ref) => ref.watch(cartProvider).length);

final cartTotalProvider = Provider<int>((ref) {
  return ref.watch(cartProvider).fold<int>(0, (sum, item) => sum + item.totalPrice);
});
