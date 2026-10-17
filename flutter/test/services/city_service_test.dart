import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/services/city_service.dart';
import 'package:mereytoi_app/services/listing_service.dart';

import '../helpers/city_fake_api.dart';

void main() {
  test('2. CityService.fetchCities parses GET /api/cities', () async {
    final (client, adapter) = fakeCityApi();
    final cities = await CityService(client).fetchCities();

    expect(adapter.requests.single.method, 'GET');
    expect(adapter.requests.single.path, '/api/cities');
    expect(cities.map((c) => c.id), testCities.map((c) => c.id));
    expect(cities.first.nameRu, 'Алматы');
    expect(cities.last.nameKz, 'Түркістан');
  });

  group('ListingService.fetchListings query', () {
    Future<Map<String, dynamic>> queryFor({
      String? categorySlug,
      String? search,
      int? cityId,
    }) async {
      final (client, adapter) = fakeCityApi();
      await ListingService(client).fetchListings(
        categorySlug: categorySlug,
        search: search,
        cityId: cityId,
      );
      return adapter.listingRequests.single.queryParameters;
    }

    test('8. null city sends no city_id at all', () async {
      expect(await queryFor(), isEmpty);
      expect(await queryFor(categorySlug: 'venues'), {'category': 'venues'});
    });

    test('9. city only', () async {
      expect(await queryFor(cityId: 1), {'city_id': 1});
    });

    test('10. category + city_id', () async {
      expect(await queryFor(categorySlug: 'venues', cityId: 2), {
        'category': 'venues',
        'city_id': 2,
      });
    });

    test('11. search + city_id', () async {
      expect(await queryFor(search: 'той', cityId: 1), {
        'search': 'той',
        'city_id': 1,
      });
    });

    test('12. category + search + city_id', () async {
      expect(await queryFor(categorySlug: 'hosts', search: 'той', cityId: 15), {
        'category': 'hosts',
        'search': 'той',
        'city_id': 15,
      });
    });
  });
}
