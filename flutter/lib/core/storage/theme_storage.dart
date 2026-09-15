import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's chosen appearance — same `shared_preferences`
/// single-key pattern `CartStorage` already established (this isn't a
/// credential, just a UI preference, so `flutter_secure_storage` would be
/// the wrong fit here).
class ThemeStorage {
  ThemeStorage._();

  static final ThemeStorage instance = ThemeStorage._();

  static const _key = 'theme_mode_v1';

  /// Never throws — a missing or corrupted stored value is treated the
  /// same as "the user never chose one yet" (`null`), so a bad stored
  /// value can never crash app startup. `null` (not a default `ThemeMode`)
  /// is the actual return type here on purpose: the caller decides what
  /// "nothing saved yet" means (this app's own answer is
  /// `ThemeMode.system`), not this storage layer.
  Future<ThemeMode?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      switch (raw) {
        case 'system':
          return ThemeMode.system;
        case 'light':
          return ThemeMode.light;
        case 'dark':
          return ThemeMode.dark;
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }

  Future<void> write(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }
}
