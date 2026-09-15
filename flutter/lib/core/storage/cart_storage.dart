import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/cart_item.dart';

/// Persists the whole cart as one JSON array under a single key — the full
/// variant snapshot (hall/menu/guests/extras/estimatedTotal), not just
/// listing ids, so a restored cart is byte-identical to what was there
/// before the app closed (brief section 10/11). `SharedPreferences` (not
/// `flutter_secure_storage`, see that package's own doc comment) is the
/// right fit here: cart contents aren't a credential, just local UI state.
class CartStorage {
  CartStorage._();

  static final CartStorage instance = CartStorage._();

  static const _key = 'cart_items_v1';

  /// Never throws — a corrupted or unreadable value is treated the same as
  /// "no saved cart yet" (an empty list), so a bad stored value can never
  /// crash app startup.
  Future<List<CartItem>> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => CartItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> write(List<CartItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(items.map((i) => i.toJson()).toList()),
    );
  }
}
