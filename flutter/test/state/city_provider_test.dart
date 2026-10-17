import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/storage/city_storage.dart';
import 'package:mereytoi_app/services/listing_service.dart';
import 'package:mereytoi_app/state/city_provider.dart';
import 'package:mereytoi_app/state/listings_provider.dart';
import 'package:mereytoi_app/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/city_fake_api.dart';

/// Shape deliberately copies `locale_provider_test.dart` — the notifier
/// mirrors `LocaleNotifier`'s restore-on-start/persist-on-write pattern.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('3. initial selectedCityId is null (Все города)', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(selectedCityIdProvider), isNull);
    await container.read(selectedCityIdProvider.notifier).ready;
    expect(container.read(selectedCityIdProvider), isNull);
    expect(container.read(selectedCityProvider), isNull);
  });

  test('4. restores a saved city_id after restart', () async {
    SharedPreferences.setMockInitialValues({'selected_city_id': 2});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(selectedCityIdProvider.notifier).ready;
    expect(container.read(selectedCityIdProvider), 2);
  });

  test(
    '5. a saved id the backend no longer has resets to null and is cleared',
    () async {
      SharedPreferences.setMockInitialValues({'selected_city_id': 99});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(selectedCityIdProvider.notifier);
      await notifier.ready;
      expect(container.read(selectedCityIdProvider), 99);

      notifier.retainOnly(testCities);
      await notifier.debugPersisted;

      expect(container.read(selectedCityIdProvider), isNull);
      expect(await CityStorage.instance.read(), isNull);
    },
  );

  test(
    '5b. the city list arriving before the restore finishes still validates',
    () async {
      SharedPreferences.setMockInitialValues({'selected_city_id': 99});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(selectedCityIdProvider.notifier);
      notifier.retainOnly(testCities); // before `ready`
      await notifier.ready;
      expect(container.read(selectedCityIdProvider), isNull);
    },
  );

  test('a valid saved id survives validation', () async {
    SharedPreferences.setMockInitialValues({'selected_city_id': 15});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(selectedCityIdProvider.notifier);
    await notifier.ready;
    notifier.retainOnly(testCities);
    expect(container.read(selectedCityIdProvider), 15);
  });

  test('corrupted stored value reads as null, never crashes', () async {
    SharedPreferences.setMockInitialValues({'selected_city_id': 'almaty'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(selectedCityIdProvider.notifier).ready;
    expect(container.read(selectedCityIdProvider), isNull);
  });

  test('6. selectCity persists the id', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(selectedCityIdProvider.notifier);
    await notifier.ready;

    notifier.selectCity(1);
    await notifier.debugPersisted;
    expect(container.read(selectedCityIdProvider), 1);
    expect(await CityStorage.instance.read(), 1);

    // A fresh container = an app restart.
    final restarted = ProviderContainer();
    addTearDown(restarted.dispose);
    await restarted.read(selectedCityIdProvider.notifier).ready;
    expect(restarted.read(selectedCityIdProvider), 1);
  });

  test('7. selecting All Cities removes the saved id', () async {
    SharedPreferences.setMockInitialValues({'selected_city_id': 2});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(selectedCityIdProvider.notifier);
    await notifier.ready;

    notifier.selectCity(null);
    await notifier.debugPersisted;

    expect(container.read(selectedCityIdProvider), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('selected_city_id'), isFalse);
  });

  test('selectedCityProvider resolves the City once the list loads', () async {
    final (client, _) = fakeCityApi();
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    container.read(selectedCityIdProvider.notifier).selectCity(4);
    expect(container.read(selectedCityProvider), isNull); // list not loaded

    await container.read(citiesProvider.future);
    expect(container.read(selectedCityProvider)?.nameKz, 'Қарағанды');
  });

  test('citiesProvider fetches once and is cached', () async {
    final (client, adapter) = fakeCityApi();
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    await container.read(citiesProvider.future);
    await container.read(citiesProvider.future);
    expect(adapter.requests.where((r) => r.path == '/api/cities').length, 1);
  });

  group('listingsProvider follows the selected city', () {
    test('restored city is in the very first listings request', () async {
      SharedPreferences.setMockInitialValues({'selected_city_id': 2});
      final (client, adapter) = fakeCityApi();
      final container = ProviderContainer(
        overrides: [
          listingServiceProvider.overrideWithValue(ListingService(client)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(listingsProvider('venues').future);

      expect(adapter.listingRequests, hasLength(1));
      expect(adapter.listingRequests.single.queryParameters, {
        'category': 'venues',
        'city_id': 2,
      });
    });

    test(
      'changing the city refetches with the same category; All Cities drops city_id',
      () async {
        final (client, adapter) = fakeCityApi();
        final container = ProviderContainer(
          overrides: [
            listingServiceProvider.overrideWithValue(ListingService(client)),
          ],
        );
        addTearDown(container.dispose);
        final sub = container.listen(listingsProvider('hosts'), (_, _) {});
        addTearDown(sub.close);

        await container.read(listingsProvider('hosts').future);
        expect(adapter.listingRequests.last.queryParameters, {
          'category': 'hosts',
        });

        container.read(selectedCityIdProvider.notifier).selectCity(1);
        await container.read(listingsProvider('hosts').future);
        expect(adapter.listingRequests.last.queryParameters, {
          'category': 'hosts',
          'city_id': 1,
        });

        container.read(selectedCityIdProvider.notifier).selectCity(2);
        await container.read(listingsProvider('hosts').future);
        expect(adapter.listingRequests.last.queryParameters, {
          'category': 'hosts',
          'city_id': 2,
        });

        container.read(selectedCityIdProvider.notifier).selectCity(null);
        await container.read(listingsProvider('hosts').future);
        expect(adapter.listingRequests.last.queryParameters, {
          'category': 'hosts',
        });
      },
    );
  });
}
