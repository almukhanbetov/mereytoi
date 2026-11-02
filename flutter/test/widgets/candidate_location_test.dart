import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/domain/event/event_status.dart';
import 'package:mereytoi_app/domain/restaurant/restaurant_location.dart';
import 'package:mereytoi_app/models/event_candidate.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/state/event_providers.dart';
import 'package:mereytoi_app/state/locale_provider.dart';
import 'package:mereytoi_app/widgets/events/candidate_location_row.dart';
import 'package:mereytoi_app/widgets/events/candidates_tab.dart';
import 'package:mereytoi_app/widgets/restaurant/restaurant_location_card.dart';
import 'package:mereytoi_app/widgets/restaurant/venue_map.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _EmptySecureStoragePlatform extends FlutterSecureStoragePlatform {
  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) => Future.value(false);
  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {}
  @override
  Future<void> deleteAll({required Map<String, String> options}) async {}
  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) => Future.value(null);
  @override
  Future<Map<String, String>> readAll({required Map<String, String> options}) =>
      Future.value(const {});
  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {}
}

const _placeId = 'EidJc3R2YW4gS29ueXIgU3RyZWV0';

/// The listing JSON exactly as GET /api/events/:id/candidates sends it
/// (Preload("Listing").Preload("Listing.Category")).
Map<String, dynamic> _listingJson(
  int id,
  String name, {
  String slug = 'venues',
  String? address,
  double? lat,
  double? lng,
  String? placeId,
  String city = 'Алматы',
}) => {
  'id': id,
  'category_id': slug == 'venues' ? 1 : 2,
  'category': {
    'id': slug == 'venues' ? 1 : 2,
    'slug': slug,
    'name_ru': slug,
    'name_kz': slug,
    'position': 1,
  },
  'name_ru': name,
  'name_kz': name,
  'city': city,
  'price': 12000,
  'is_active': true,
  'address': ?address,
  'latitude': ?lat,
  'longitude': ?lng,
  'place_id': ?placeId,
};

EventCandidate _candidate(int id, Map<String, dynamic> listing) =>
    EventCandidate.fromJson({
      'id': id,
      'event_id': 1,
      'listing_id': listing['id'],
      'listing': listing,
      'status': candidateShortlisted,
      'added_by_id': 1,
      'created_at': '2026-11-02T10:00:00Z',
      'updated_at': '2026-11-02T10:00:00Z',
    });

final _grandHall = _listingJson(
  1,
  'Almaty Grand Hall',
  address: 'улица Иштван Коныра, Алматы, Казахстан',
  lat: 43.2721509,
  lng: 76.9976112,
  placeId: _placeId,
);
final _noLocationHall = _listingJson(2, 'Nomad Banquet House');
final _host = _listingJson(3, 'Динара Касымова', slug: 'hosts');

void main() {
  setUp(() {
    FlutterSecureStoragePlatform.instance = _EmptySecureStoragePlatform();
    // The native map view can't run in a widget test: stand in a
    // placeholder that shows what the map was told to display.
    VenueMap.debugMapBuilder = (data) => Text(
      'map ${data.target.latitude},${data.target.longitude} '
      '${data.marker.infoWindow.title} · ${data.marker.infoWindow.snippet}',
    );
  });
  tearDown(() => VenueMap.debugMapBuilder = null);

  group('model', () {
    test('candidate listing reads the API location fields', () {
      final l = _candidate(1, _grandHall).listing!;
      expect(l.latitude, 43.2721509);
      expect(l.longitude, 76.9976112);
      expect(l.address, 'улица Иштван Коныра, Алматы, Казахстан');
      expect(l.placeId, _placeId);
      expect(l.category?.slug, 'venues');
      expect(hasVenueLocation(l), isTrue);
    });

    test('a city alone is not a venue location', () {
      final l = _candidate(2, _noLocationHall).listing!;
      expect(l.hasCoords, isFalse);
      expect(hasVenueLocation(l), isFalse);
      expect(restaurantMapUrl(l), isNull);
    });

    test('map link points at the venue, never at 0,0 or swapped', () {
      final l = _candidate(1, _grandHall).listing!;
      final url = restaurantMapUrl(l)!;
      expect(url, contains('query=43.2721509,76.9976112'));
      expect(url, contains('query_place_id=$_placeId'));
      final byAddress = Listing.fromJson(
        _listingJson(4, 'X', address: 'пр. Абая 1'),
      );
      expect(
        restaurantMapUrl(byAddress),
        'https://www.google.com/maps/search/?api=1&query='
        '${Uri.encodeComponent('пр. Абая 1')}',
      );
    });
  });

  Future<void> pumpCandidates(
    WidgetTester tester,
    List<EventCandidate> candidates, {
    AppLocale locale = AppLocale.ru,
    ThemeData? theme,
  }) async {
    SharedPreferences.setMockInitialValues({
      if (locale != AppLocale.ru) 'app_locale_v1': locale.name,
    });
    tester.view.physicalSize = const Size(360, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eventCandidatesProvider(
            1,
          ).overrideWith((ref) => Future.value(candidates)),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.light,
          home: const Scaffold(
            body: CandidatesTab(eventId: 1, myRole: 'owner'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('embedded venue map', () {
    test('marker and camera use the restaurant\'s own coordinates', () {
      final data = VenueMapData.of(
        _candidate(1, _grandHall).listing!,
        AppLocale.ru,
      )!;
      expect(data.target.latitude, 43.2721509);
      expect(data.target.longitude, 76.9976112);
      expect(data.marker.position, data.target);
      expect(data.marker.infoWindow.title, 'Almaty Grand Hall');
      expect(
        data.marker.infoWindow.snippet,
        'улица Иштван Коныра, Алматы, Казахстан',
      );
      expect(VenueMapData.zoom, 15);
    });

    test('no coordinates → no map data (no guessed point)', () {
      expect(
        VenueMapData.of(_candidate(2, _noLocationHall).listing!, AppLocale.ru),
        isNull,
      );
      final addressOnly = Listing.fromJson(
        _listingJson(4, 'X', address: 'пр. Абая 1'),
      );
      expect(VenueMapData.of(addressOnly, AppLocale.ru), isNull);
    });

    test('invalid coordinates are never plotted', () {
      for (final (lat, lng) in [
        (0.0, 0.0),
        (double.nan, 76.9),
        (43.2, double.nan),
        (double.infinity, 76.9),
        (91.0, 76.9),
        (-90.5, 76.9),
        (43.2, 180.5),
        (43.2, -181.0),
      ]) {
        final l = Listing.fromJson(_listingJson(6, 'X', lat: lat, lng: lng));
        expect(l.hasCoords, isFalse, reason: '$lat,$lng');
        expect(VenueMapData.of(l, AppLocale.ru), isNull, reason: '$lat,$lng');
      }
      // Edges of the valid range, and a point on one zero axis, still count.
      expect(isValidCoordinate(90, 180), isTrue);
      expect(isValidCoordinate(-90, -180), isTrue);
      expect(isValidCoordinate(0, 76.9), isTrue);
    });

    test('VenueMap takes the raw venue fields', () {
      const map = VenueMap(
        latitude: 43.24346,
        longitude: 76.9559192,
        venueName: 'Magauya Grand Hall',
        address: 'пр-т. Абая 1, Алматы',
      );
      final data = map.data!;
      expect(data.target, const LatLng(43.24346, 76.9559192));
      expect(data.marker.position, data.target);
      expect(data.marker.infoWindow.title, 'Magauya Grand Hall');
      expect(data.marker.infoWindow.snippet, 'пр-т. Абая 1, Алматы');
      expect(
        const VenueMap(latitude: 0, longitude: 0, venueName: 'X').data,
        isNull,
      );
    });

    testWidgets('VenueMap with an invalid point renders no map at all', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: VenueMap(latitude: null, longitude: 76.9, venueName: 'X'),
          ),
        ),
      );
      expect(find.textContaining('map '), findsNothing);
      expect(find.byType(ClipRRect), findsNothing);
    });

    testWidgets('0,0 coordinates without an address → fallback, no map, '
        'no link to 0,0', (tester) async {
      await pumpCandidates(tester, [
        _candidate(7, _listingJson(7, 'Zero Hall', lat: 0, lng: 0)),
      ]);
      expect(find.byKey(const ValueKey('candidate-venue-map')), findsNothing);
      expect(
        find.byKey(const ValueKey('candidate-location-unknown')),
        findsOneWidget,
      );
      expect(find.text('На карте'), findsNothing);
    });

    testWidgets('out-of-range coordinates with an address → address links '
        'only, no map', (tester) async {
      await pumpCandidates(tester, [
        _candidate(
          8,
          _listingJson(8, 'Bad Hall', address: 'пр. Абая 1', lat: 95, lng: 76),
        ),
      ]);
      expect(find.byKey(const ValueKey('candidate-venue-map')), findsNothing);
      expect(find.text('пр. Абая 1'), findsOneWidget);
      expect(find.text('На карте'), findsOneWidget);
    });

    testWidgets('a restaurant with coordinates gets the map between its '
        'address and the external links', (tester) async {
      await pumpCandidates(tester, [_candidate(1, _grandHall)]);
      final map = find.byKey(const ValueKey('candidate-venue-map'));
      expect(map, findsOneWidget);
      expect(
        find.text(
          'map 43.2721509,76.9976112 Almaty Grand Hall · '
          'улица Иштван Коныра, Алматы, Казахстан',
        ),
        findsOneWidget,
      );
      double top(Finder f) => tester.getTopLeft(f).dy;
      expect(
        top(find.text('улица Иштван Коныра, Алматы, Казахстан')),
        lessThan(top(map)),
      );
      expect(top(map), lessThan(top(find.text('На карте'))));
      expect(tester.getSize(map).height, 240);
      expect(find.text('Маршрут'), findsOneWidget);
    });

    testWidgets('an address without coordinates: links, but no map', (
      tester,
    ) async {
      await pumpCandidates(tester, [
        _candidate(4, _listingJson(4, 'Sultan Hall', address: 'пр. Абая 1')),
      ]);
      expect(find.byKey(const ValueKey('candidate-venue-map')), findsNothing);
      expect(find.text('пр. Абая 1'), findsOneWidget);
      expect(find.text('На карте'), findsOneWidget);
    });

    testWidgets('another restaurant in the same slot moves the map to it', (
      tester,
    ) async {
      Future<void> pumpRow(Map<String, dynamic> json) => tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: CandidateLocationRow(
              listing: Listing.fromJson(json),
              locale: AppLocale.ru,
            ),
          ),
        ),
      );
      await pumpRow(_grandHall);
      expect(find.textContaining('map 43.2721509,76.9976112'), findsOneWidget);
      final mapState = tester.state(find.byType(VenueMap));
      await pumpRow(
        _listingJson(
          5,
          'Magauya Grand Hall',
          address: 'пр-т. Абая 1, Алматы',
          lat: 43.24346,
          lng: 76.9559192,
        ),
      );
      // Same map view, updated in place (didUpdateWidget moves the camera).
      expect(tester.state(find.byType(VenueMap)), same(mapState));
      expect(find.textContaining('map 43.2721509'), findsNothing);
      expect(
        find.textContaining('map 43.24346,76.9559192 Magauya Grand Hall'),
        findsOneWidget,
      );
      expect(find.text('Маршрут'), findsOneWidget);
    });

    testWidgets('no map for a restaurant without coordinates or a host', (
      tester,
    ) async {
      await pumpCandidates(tester, [
        _candidate(2, _noLocationHall),
        _candidate(3, _host),
      ]);
      expect(find.byKey(const ValueKey('candidate-venue-map')), findsNothing);
      expect(find.textContaining('map '), findsNothing);
    });
  });

  testWidgets('a restaurant with a location shows its address and map links', (
    tester,
  ) async {
    await pumpCandidates(tester, [_candidate(1, _grandHall)]);
    expect(find.byKey(const ValueKey('candidate-location')), findsOneWidget);
    expect(find.text('улица Иштван Коныра, Алматы, Казахстан'), findsOneWidget);
    expect(find.text('На карте'), findsOneWidget);
    expect(find.text('Маршрут'), findsOneWidget);
  });

  testWidgets('a restaurant without a location says so, with no map links', (
    tester,
  ) async {
    await pumpCandidates(tester, [_candidate(2, _noLocationHall)]);
    expect(
      find.byKey(const ValueKey('candidate-location-unknown')),
      findsOneWidget,
    );
    expect(
      find.text('Алматы · Местоположение пока не указано'),
      findsOneWidget,
    );
    expect(find.text('На карте'), findsNothing);
    expect(find.text('Маршрут'), findsNothing);
  });

  testWidgets('non-restaurant services get no location line', (tester) async {
    await pumpCandidates(tester, [_candidate(3, _host)]);
    expect(find.text('Динара Касымова'), findsOneWidget);
    expect(find.byKey(const ValueKey('candidate-location')), findsNothing);
    expect(
      find.byKey(const ValueKey('candidate-location-unknown')),
      findsNothing,
    );
  });

  testWidgets('each candidate shows its own venue', (tester) async {
    await pumpCandidates(tester, [
      _candidate(1, _grandHall),
      _candidate(2, _noLocationHall),
      _candidate(3, _host),
    ]);
    expect(find.byKey(const ValueKey('candidate-location')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('candidate-location-unknown')),
      findsOneWidget,
    );
  });

  group('no overflow', () {
    final themes = <(String, ThemeData Function())>[
      ('light', () => AppTheme.light),
      ('dark', () => AppTheme.dark),
    ];
    for (final theme in themes) {
      for (final locale in AppLocale.values) {
        testWidgets('${theme.$1} · ${locale.name}', (tester) async {
          await pumpCandidates(
            tester,
            [
              _candidate(1, _grandHall),
              _candidate(2, _noLocationHall),
              _candidate(3, _host),
            ],
            locale: locale,
            theme: theme.$2(),
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('restaurant page location card', () {
    Future<void> pumpCard(WidgetTester tester, Listing listing) =>
        tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: RestaurantLocationCard(
                listing: listing,
                locale: AppLocale.ru,
              ),
            ),
          ),
        );

    testWidgets('known location → route button', (tester) async {
      await pumpCard(tester, Listing.fromJson(_grandHall));
      expect(find.text('Построить маршрут'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('restaurant-location-unknown')),
        findsNothing,
      );
    });

    testWidgets('city only → «not specified», no route to the city', (
      tester,
    ) async {
      await pumpCard(tester, Listing.fromJson(_noLocationHall));
      expect(find.text('Алматы'), findsOneWidget);
      expect(find.text('Местоположение пока не указано'), findsOneWidget);
      expect(find.text('Построить маршрут'), findsNothing);
    });
  });
}
