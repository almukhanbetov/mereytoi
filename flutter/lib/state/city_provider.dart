import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/city_storage.dart';
import '../models/city.dart';
import 'providers.dart';

/// GET /api/cities, fetched once per app session and cached by Riverpod —
/// opening the city sheet again or typing in its search never re-requests
/// it. `ref.invalidate(citiesProvider)` is the retry path (= loadCities).
final citiesProvider = FutureProvider<List<City>>((ref) {
  return ref.watch(cityServiceProvider).fetchCities();
});

/// The selected city's ID; `null` means "Все города". Kept separate from
/// [citiesProvider] on purpose: listings depend only on this ID, so the
/// city list loading/failing never refetches any listing.
///
/// Restored from [CityStorage] on construction and persisted on every
/// change — the same restore-on-start/persist-on-write shape as
/// `LocaleNotifier`.
class SelectedCityNotifier extends StateNotifier<int?> {
  SelectedCityNotifier(this._storage) : super(null) {
    _readyCompleter = _restore();
  }

  final CityStorage _storage;
  late final Future<void> _readyCompleter;

  /// The last city list seen by [retainOnly] — lets a restore that
  /// finishes *after* the list arrived still be validated.
  List<City>? _knownCities;

  /// Resolves once the initial restore-from-storage attempt has finished.
  /// `listingsProvider` awaits it so the first listings request already
  /// carries the saved city instead of fetching "all cities" first.
  Future<void> get ready => _readyCompleter;

  Future<void>? _lastPersist;

  @visibleForTesting
  Future<void> get debugPersisted => _lastPersist ?? Future.value();

  Future<void> _restore() async {
    final saved = await _storage.read();
    if (!mounted) return;
    if (saved != null) state = saved;
    final known = _knownCities;
    if (known != null) retainOnly(known);
  }

  void selectCity(int? cityId) {
    state = cityId;
    _lastPersist = _storage.write(cityId);
  }

  /// Drops a saved ID that the backend directory no longer has (falls back
  /// to "Все города" and clears storage). A no-op while nothing is selected.
  void retainOnly(List<City> cities) {
    _knownCities = cities;
    final id = state;
    if (id != null && !cities.any((c) => c.id == id)) selectCity(null);
  }
}

final selectedCityIdProvider =
    StateNotifierProvider<SelectedCityNotifier, int?>((ref) {
      return SelectedCityNotifier(CityStorage.instance);
    });

/// The selected [City] itself, for labels — `null` both for "Все города"
/// and while the city list hasn't loaded yet.
final selectedCityProvider = Provider<City?>((ref) {
  final id = ref.watch(selectedCityIdProvider);
  if (id == null) return null;
  final cities = ref.watch(citiesProvider).valueOrNull;
  if (cities == null) return null;
  for (final city in cities) {
    if (city.id == id) return city;
  }
  return null;
});
