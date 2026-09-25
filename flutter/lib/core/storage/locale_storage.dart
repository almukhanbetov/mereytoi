import 'package:shared_preferences/shared_preferences.dart';

import '../../state/locale_provider.dart';

/// Persists the user's chosen interface language — same single-key
/// `shared_preferences` pattern [ThemeStorage] already established for the
/// appearance toggle (a UI preference, not a credential, so
/// `flutter_secure_storage` would be the wrong fit here).
class LocaleStorage {
  LocaleStorage._();

  static final LocaleStorage instance = LocaleStorage._();

  static const _key = 'app_locale_v1';

  /// Never throws — a missing or corrupted stored value is treated the
  /// same as "the user never chose one yet" (`null`), so a bad stored
  /// value can never crash app startup.
  Future<AppLocale?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      switch (raw) {
        case 'ru':
          return AppLocale.ru;
        case 'kz':
          return AppLocale.kz;
        case 'en':
          return AppLocale.en;
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }

  Future<void> write(AppLocale locale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, locale.name);
  }
}
