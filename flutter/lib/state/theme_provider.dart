import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/theme_storage.dart';

/// The user's chosen appearance — `system` (the default, before any
/// explicit choice is ever made) / `light` / `dark`. Restored from
/// `ThemeStorage` on construction and persisted on every change, the same
/// restore-on-start/persist-on-write shape `CartNotifier` already
/// established for its own local state.
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(this._storage) : super(ThemeMode.system) {
    _readyCompleter = _restore();
  }

  final ThemeStorage _storage;
  late final Future<void> _readyCompleter;

  /// Resolves once the initial restore-from-storage attempt has finished —
  /// lets a test await past hydration deterministically instead of
  /// guessing at a delay.
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
    // `null` means "nothing saved yet" — leaves the constructor's own
    // `ThemeMode.system` default in place, exactly the brief's own "если
    // нет сохранённой — использовать ThemeMode.system".
    if (saved != null) state = saved;
  }

  void setMode(ThemeMode mode) {
    state = mode;
    _lastPersist = _storage.write(mode);
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((
  ref,
) {
  return ThemeModeNotifier(ThemeStorage.instance);
});
