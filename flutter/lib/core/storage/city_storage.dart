import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's chosen city as its backend ID — same single-key
/// `shared_preferences` pattern as [LocaleStorage]/[ThemeStorage] (a UI
/// preference, not a credential). No key at all means "Все города".
class CityStorage {
  CityStorage._();

  static final CityStorage instance = CityStorage._();

  static const _key = 'selected_city_id';

  /// Never throws — a missing or corrupted stored value reads as `null`
  /// ("Все города"), so a bad stored value can never crash app startup.
  Future<int?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.get(_key);
      return raw is int && raw > 0 ? raw : null;
    } catch (_) {
      return null;
    }
  }

  /// `null` removes the key rather than storing a sentinel.
  Future<void> write(int? cityId) async {
    final prefs = await SharedPreferences.getInstance();
    if (cityId == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setInt(_key, cityId);
    }
  }
}
