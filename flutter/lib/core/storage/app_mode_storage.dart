import 'package:shared_preferences/shared_preferences.dart';

import '../../state/app_mode_provider.dart';

/// Persists the last chosen app mode (for an event / for business) — the
/// same single-key `shared_preferences` pattern as `ThemeStorage`. It's a
/// UI preference only, never a role on the backend.
class AppModeStorage {
  AppModeStorage._();

  static final AppModeStorage instance = AppModeStorage._();

  static const _key = 'app_mode_v1';

  /// Never throws: a missing or corrupted value reads as `null` — "the
  /// user hasn't chosen yet".
  Future<AppMode?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return switch (prefs.getString(_key)) {
        'client' => AppMode.client,
        'business' => AppMode.business,
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }

  Future<void> write(AppMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }
}
