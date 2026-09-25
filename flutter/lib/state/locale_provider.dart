import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/locale_storage.dart';

/// The site supports RU/KZ via a simple client-side toggle (see
/// frontend/src/context/AppProviders.jsx's `T`/`useLang`) rather than
/// full Flutter `intl` message catalogs — the API already returns both
/// `name_ru`/`name_kz` per record, so the app just needs to remember which
/// one the user wants and a tiny helper for the app's own static strings.
///
/// `en` is a full third value (Этап 10Б-А3/А5 made it reachable from the
/// UI's own language sheet) because the site itself has started adding
/// English copy for one flow (`<T ru kz en/>` in the event-request/booking
/// area, see frontend/src/context/AppProviders.jsx's own `T` component) —
/// this keeps the app's helper shape compatible with that.
enum AppLocale { ru, kz, en }

/// The user's chosen interface language. Restored from [LocaleStorage] on
/// construction and persisted on every change — the exact
/// restore-on-start/persist-on-write shape `ThemeModeNotifier` already
/// established for the appearance toggle.
class LocaleNotifier extends StateNotifier<AppLocale> {
  LocaleNotifier(this._storage) : super(AppLocale.ru) {
    _readyCompleter = _restore();
  }

  final LocaleStorage _storage;
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
    // `AppLocale.ru` default in place.
    if (saved != null) state = saved;
  }

  void setLocale(AppLocale locale) {
    state = locale;
    _lastPersist = _storage.write(locale);
  }
}

final localeProvider = StateNotifierProvider<LocaleNotifier, AppLocale>((ref) {
  return LocaleNotifier(LocaleStorage.instance);
});

/// Picks between hardcoded strings by locale — the Dart equivalent of the
/// site's `<T ru="..." kz="..." en="..."/>`. `en` is optional and falls
/// back to `ru`, mirroring `T`'s own `en ?? ru` behavior exactly — a call
/// site that never passes `en` keeps working unchanged even once
/// `AppLocale.en` becomes reachable.
String t(
  AppLocale locale, {
  required String ru,
  required String kz,
  String? en,
}) {
  switch (locale) {
    case AppLocale.kz:
      return kz;
    case AppLocale.en:
      return en ?? ru;
    case AppLocale.ru:
      return ru;
  }
}
