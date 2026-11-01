import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/models/category.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/models/site_statistics.dart';
import 'package:mereytoi_app/screens/home/home_screen.dart';
import 'package:mereytoi_app/state/categories_provider.dart';
import 'package:mereytoi_app/state/listings_provider.dart';
import 'package:mereytoi_app/state/statistics_provider.dart';
import 'package:mereytoi_app/widgets/service_card.dart';

/// Same empty in-memory secure storage other widget tests in this suite
/// use — `HomeScreen`'s own account button reads `authProvider`, whose
/// notifier restores a session from `TokenStorage` on construction.
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

Listing _longListing(int id, String category) => Listing(
  id: id,
  categoryId: 1,
  category: Category(
    id: 1,
    slug: category,
    nameRu: 'Очень длинное название категории для проверки переноса строк',
    nameKz: 'Ұзақ санат',
    position: 0,
  ),
  nameRu:
      'Очень длинное название услуги или ресторана, которое не должно ломать карточку карусели',
  nameKz: 'Ұзақ атау',
  descriptionRu: '',
  descriptionKz: '',
  city: 'Алматы (очень длинное уточнение района)',
  phone: '+7 700 123 45 67',
  price: 123456789,
  minGuests: 0,
  maxGuests: 0,
  rating: 4.9,
  emoji: '',
  colorFrom: '',
  colorTo: '',
  imageUrls: const [],
  isActive: true,
);

void main() {
  setUp(() {
    FlutterSecureStoragePlatform.instance = _EmptySecureStoragePlatform();
  });

  Future<void> pumpHome(
    WidgetTester tester, {
    required Size size,
    required List<Listing> services,
    required List<Listing> restaurants,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          categoriesProvider.overrideWith(
            (ref) => Future.value(const <Category>[]),
          ),
          listingsProvider(null).overrideWith((ref) => Future.value(services)),
          listingsProvider(
            'venues',
          ).overrideWith((ref) => Future.value(restaurants)),
          statisticsProvider.overrideWith(
            (ref) => Future.value(
              const SiteStatistics(
                eventsCount: 15000,
                happyGuestsCount: 500000,
                yearsExperience: 8,
                citiesCount: 12,
              ),
            ),
          ),
        ],
        child: MediaQuery(
          data: MediaQueryData(size: size),
          child: MaterialApp(theme: AppTheme.dark, home: const HomeScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final size in [Size(320, 700), Size(360, 800)]) {
    testWidgets(
      'HomeScreen shows a short «Популярное» block with long content, no overflow, at ${size.width.toInt()}px',
      (tester) async {
        await pumpHome(
          tester,
          size: size,
          services: [for (var i = 1; i <= 8; i++) _longListing(i, 'hosts')],
          restaurants: [_longListing(20, 'venues')],
        );

        // The block sits below the hero and categories — scroll to it
        // like a user would.
        await tester.scrollUntilVisible(
          find.text('Популярное'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Популярное'), findsOneWidget);
        await tester.drag(
          find.byType(Scrollable).first,
          const Offset(0, -3000),
        );
        await tester.pumpAndSettle();

        // A glimpse, not the catalog: at most four cards, and no separate
        // restaurants rail.
        expect(find.byType(ServiceGridCard), findsNWidgets(4));
        expect(find.text('Рестораны'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'HomeScreen hides «Популярное» entirely when there are no services (no dead empty state)',
    (tester) async {
      await pumpHome(
        tester,
        size: const Size(360, 800),
        services: const [],
        restaurants: const [],
      );

      // Scroll all the way down, to confirm its absence is real (the
      // empty-data branch), not just off-screen.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
      await tester.pumpAndSettle();

      expect(find.text('Популярное'), findsNothing);
      expect(find.byType(ServiceGridCard), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
