import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/core/utils/format.dart';
import 'package:mereytoi_app/models/category.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/screens/restaurant/restaurant_detail_screen.dart';
import 'package:mereytoi_app/screens/service_detail/service_detail_screen.dart';
import 'package:mereytoi_app/screens/services/services_screen.dart';
import 'package:mereytoi_app/services/listing_service.dart';
import 'package:mereytoi_app/state/categories_provider.dart';
import 'package:mereytoi_app/state/listings_provider.dart';
import 'package:mereytoi_app/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/city_fake_api.dart';

Listing _listing(int id, int views, {String name = 'Услуга'}) =>
    Listing.fromJson({
      'id': id,
      'category_id': 2,
      'name_ru': name,
      'name_kz': name,
      'description_ru': '',
      'description_kz': '',
      'city': 'Алматы',
      'price': 1000,
      'rating': 0.0,
      'is_active': true,
      'view_count': views,
    });

/// The server: it holds the only number, and repeats aren't counted.
class _Service extends ListingService {
  _Service(super.client);

  int views = 12344;
  bool counted = true;
  bool fails = false;
  final recorded = <int>[];

  @override
  Future<bool> recordView(int id) async {
    recorded.add(id);
    if (fails) throw Exception('network');
    if (counted) views++;
    return counted;
  }

  @override
  Future<Listing> fetchById(int id) async => _listing(id, views);
}

void main() {
  late _Service service;

  Future<ProviderContainer> pump(WidgetTester tester, Widget home) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (client, _) = fakeCityApi();
    service = _Service(client);
    final container = ProviderContainer(
      overrides: [
        listingServiceProvider.overrideWithValue(service),
        categoriesProvider.overrideWith(
          (ref) => Future.value(const <Category>[]),
        ),
        listingsProvider(
          null,
        ).overrideWith((ref) => Future.value([_listing(1, 7), _listing(2, 0)])),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: AppTheme.light, home: home),
      ),
    );
    return container;
  }

  Finder chip() => find.byKey(const ValueKey('listing-view-count'));

  test('formatCount groups thousands and never goes negative', () {
    expect(formatCount(0), '0');
    expect(formatCount(12345).replaceAll(' ', ' '), '12 345');
    expect(formatCount(-1), '0');
  });

  testWidgets('list: each card shows its own number and nothing is counted', (
    tester,
  ) async {
    await pump(tester, const ServicesScreen());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('service-view-count')), findsNWidgets(2));
    expect(find.text('7'), findsOneWidget);
    expect(find.text('0'), findsOneWidget); // a real zero, not hidden
    expect(service.recorded, isEmpty);
  });

  for (final dark in [false, true]) {
    testWidgets(
      'service page: counted once, the server number is shown · dark=$dark',
      (tester) async {
        await pump(tester, const ServiceDetailScreen(listingId: 5));
        if (dark) {
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: ProviderScope.containerOf(
                tester.element(find.byType(ServiceDetailScreen)),
              ),
              child: MaterialApp(
                theme: AppTheme.dark,
                home: const ServiceDetailScreen(listingId: 5),
              ),
            ),
          );
        }
        await tester.pumpAndSettle();
        expect(service.recorded, [5]);
        expect(
          find.descendant(of: chip(), matching: find.text(formatCount(12345))),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('rebuilds of the page don\'t count again', (tester) async {
    await pump(tester, const ServiceDetailScreen(listingId: 5));
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(ServiceDetailScreen));
    for (var i = 0; i < 5; i++) {
      // ignore: invalid_use_of_protected_member
      state.setState(() {});
      await tester.pump();
    }
    expect(service.recorded, [5]);
  });

  testWidgets('a repeat the server refuses changes nothing', (tester) async {
    final container = await pump(tester, const SizedBox());
    service.counted = false;
    await recordListingView(container, 5);
    expect(service.recorded, [5]);
    expect(service.views, 12344);
  });

  testWidgets('a failed count stays silent', (tester) async {
    final container = await pump(tester, const SizedBox());
    service.fails = true;
    await recordListingView(container, 5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a restaurant page counts too', (tester) async {
    await pump(tester, const RestaurantDetailScreen(listingId: 9));
    await tester.pumpAndSettle();
    expect(service.recorded, [9]);
  });
}
