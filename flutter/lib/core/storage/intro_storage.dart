import 'package:shared_preferences/shared_preferences.dart';

/// Remembers that the first-launch intro has been seen — the same
/// single-key `shared_preferences` pattern as `ThemeStorage`.
class IntroStorage {
  IntroStorage._();

  static final IntroStorage instance = IntroStorage._();

  static const _key = 'intro_seen_v1';

  /// Never throws: anything unreadable counts as "not seen yet".
  Future<bool> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> markSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, true);
    } catch (_) {
      // Worst case the intro shows once more.
    }
  }
}
