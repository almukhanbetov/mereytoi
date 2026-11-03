import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/network/api_client.dart';
import 'package:mereytoi_app/core/network/api_exception.dart';
import 'package:mereytoi_app/services/auth_service.dart';
import 'package:mereytoi_app/services/city_service.dart';
import 'package:mereytoi_app/services/listing_service.dart';

// Real production responses (captured 2026-11-03 from https://mereytoi.kz,
// phone/WhatsApp numbers masked; the register success body comes from a
// local backend with the token replaced) run through the real services, so
// a model that stops fitting the live API fails here, not on a tester's
// phone as «Не удалось загрузить данные».

String _fixture(String name) =>
    File('test/fixtures/prod_api/$name').readAsStringSync();

/// Answers each path with a fixture body and status.
class _FixtureAdapter implements HttpClientAdapter {
  _FixtureAdapter(this.routes);

  final Map<String, (int, String)> routes;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final (status, body) = routes[options.path]!;
    return ResponseBody.fromBytes(
      utf8.encode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ApiClient _client(Map<String, (int, String)> routes) {
  final client = ApiClient.test(tokenProvider: () async => null);
  client.debugDio.httpClientAdapter = _FixtureAdapter(routes);
  return client;
}

void main() {
  test('GET /api/cities (production) parses into cities', () async {
    final cities = await CityService(
      _client({'/api/cities': (200, _fixture('cities.json'))}),
    ).fetchCities();
    expect(cities, isNotEmpty);
    expect(cities.map((c) => c.id).toSet().length, cities.length);
  });

  test('GET /api/listings (production) parses every listing', () async {
    final body = _fixture('listings.json');
    final raw = (jsonDecode(body) as Map)['listings'] as List;
    final listings = await ListingService(
      _client({'/api/listings': (200, body)}),
    ).fetchListings();
    expect(listings, hasLength(raw.length));
    expect(listings.length, greaterThan(50));
    // Long Russian descriptions with emoji survive intact.
    final withEmoji = listings.where(
      (l) => RegExp(
        r'[\u{1F300}-\u{1FAFF}]',
        unicode: true,
      ).hasMatch('${l.descriptionRu}${l.descriptionKz}'),
    );
    expect(withEmoji, isNotEmpty);
  });

  test('listing fields the API may send as null or leave out', () async {
    final listing =
        ((jsonDecode(_fixture('listings.json')) as Map)['listings'] as List)
                .first
            as Map<String, dynamic>;
    final variants = <Map<String, dynamic>>[
      {...listing, 'image_urls': null, 'video_urls': null},
      {...listing}
        ..remove('image_urls')
        ..remove('video_urls')
        ..remove('rating')
        ..remove('city'),
      {...listing, 'rating': null, 'price': null, 'emoji': null},
      {...listing, 'rating': 4},
    ];
    for (final v in variants) {
      final listings = await ListingService(
        _client({
          '/api/listings': (
            200,
            jsonEncode({
              'listings': [v],
            }),
          ),
        }),
      ).fetchListings();
      expect(listings.single.id, listing['id']);
    }
  });

  test('POST /api/auth/register success parses user + token', () async {
    final result =
        await AuthService(
          _client({'/api/auth/register': (201, _fixture('register_201.json'))}),
        ).register(
          name: 'Fixture User',
          email: 'fixture.user@example.com',
          password: 'x',
        );
    expect(result.token, 'test-token');
    expect(result.user.email, 'fixture.user@example.com');
  });

  test('POST /api/auth/register validation error is an HTTP 400, not a '
      'connection problem', () async {
    await expectLater(
      AuthService(
        _client({'/api/auth/register': (400, _fixture('register_400.json'))}),
      ).register(name: '', email: '', password: ''),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 400)
            .having((e) => e.diagnosticCode, 'code', 'ERR_HTTP_400'),
      ),
    );
  });
}
