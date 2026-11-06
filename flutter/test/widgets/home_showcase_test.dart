import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/models/category.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/models/site_statistics.dart';
import 'package:mereytoi_app/screens/home/home_screen.dart';
import 'package:mereytoi_app/screens/service_detail/service_detail_screen.dart';
import 'package:mereytoi_app/screens/services/services_screen.dart';
import 'package:mereytoi_app/state/categories_provider.dart';
import 'package:mereytoi_app/state/listings_provider.dart';
import 'package:mereytoi_app/state/locale_provider.dart';
import 'package:mereytoi_app/state/providers.dart';
import 'package:mereytoi_app/state/statistics_provider.dart';
import 'package:mereytoi_app/widgets/category_card.dart';
import 'package:mereytoi_app/widgets/city_selector.dart';
import 'package:mereytoi_app/widgets/service_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/city_fake_api.dart';

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

const _categories = [
  Category(
    id: 1,
    slug: 'venues',
    nameRu: 'Рестораны и локации',
    nameKz: 'Мейрамханалар мен локациялар',
    position: 1,
  ),
  Category(
    id: 2,
    slug: 'hosts',
    nameRu: 'Ведущие и шоумены',
    nameKz: 'Жүргізушілер',
    position: 2,
  ),
  Category(
    id: 3,
    slug: 'shows',
    nameRu: 'Шоу-программы',
    nameKz: 'Шоу-бағдарламалар',
    position: 3,
  ),
  Category(
    id: 4,
    slug: 'artists',
    nameRu: 'Артисты и исполнители',
    nameKz: 'Әртістер мен орындаушылар',
    position: 4,
  ),
  Category(
    id: 5,
    slug: 'stars',
    nameRu: 'Звёзды эстрады',
    nameKz: 'Эстрада жұлдыздары',
    position: 5,
  ),
  Category(
    id: 6,
    slug: 'animators',
    nameRu: 'Аниматоры',
    nameKz: 'Аниматорлар',
    position: 6,
  ),
];

Listing _listing(int id) => Listing(
  id: id,
  categoryId: 2,
  category: _categories[1],
  nameRu: 'Услуга $id',
  nameKz: 'Қызмет $id',
  descriptionRu: '',
  descriptionKz: '',
  city: 'Алматы',
  phone: '',
  price: 100000 * id,
  minGuests: 0,
  maxGuests: 0,
  rating: 5,
  emoji: '',
  colorFrom: '',
  colorTo: '',
  imageUrls: const [],
  isActive: true,
);

final _listings = [for (var i = 1; i <= 10; i++) _listing(i)];

void main() {
  setUp(() {
    FlutterSecureStoragePlatform.instance = _EmptySecureStoragePlatform();
  });

  Future<void> pumpHome(
    WidgetTester tester, {
    Size size = const Size(390, 3000),
    ThemeData Function()? theme,
    AppLocale locale = AppLocale.ru,
    double textScale = 1,
  }) async {
    SharedPreferences.setMockInitialValues({
      if (locale != AppLocale.ru) 'app_locale_v1': locale.name,
    });
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (client, _) = fakeCityApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(client),
          categoriesProvider.overrideWith((ref) => Future.value(_categories)),
          for (final slug in [null, ..._categories.map((c) => c.slug)])
            listingsProvider(
              slug,
            ).overrideWith((ref) => Future.value(_listings)),
          for (final l in _listings)
            listingDetailProvider(l.id).overrideWith((ref) => Future.value(l)),
          statisticsProvider.overrideWith(
            (ref) => Future.value(
              const SiteStatistics(
                eventsCount: 1200,
                happyGuestsCount: 20000,
                yearsExperience: 10,
                citiesCount: 1,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: (theme ?? () => AppTheme.light)(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  ServicesScreen catalog(WidgetTester tester) =>
      tester.widget<ServicesScreen>(find.byType(ServicesScreen));

  testWidgets('a short showcase: hero → city → provider card → 4 categories '
      '→ «Все услуги» → 4 popular', (tester) async {
    await pumpHome(tester);
    double top(Finder f) => tester.getTopLeft(f).dy;
    final hero = find.text('Той вашей мечты');
    final city = find.byType(CitySelectorButton);
    final categories = find.text('Что мы предлагаем'.toUpperCase());
    final allServices = find.byKey(const ValueKey('home-all-services'));
    final popular = find.text('Популярное');
    final provider = find.byKey(const ValueKey('provider-promo-card'));
    for (final f in [hero, city, categories, allServices, popular, provider]) {
      expect(f, findsOneWidget);
    }
    expect(top(hero), lessThan(top(city)));
    expect(top(city), lessThan(top(provider)));
    expect(top(provider), lessThan(top(categories)));
    expect(top(categories), lessThan(top(allServices)));
    expect(top(allServices), lessThan(top(popular)));

    // Seen early, but secondary: much lower than the hero block.
    final heroBlock = find.ancestor(of: hero, matching: find.byType(Container));
    expect(
      tester.getSize(provider).height,
      lessThan(tester.getSize(heroBlock.first).height / 2),
    );

    // Not a second catalog: 4 of 6 categories, 4 of 10 services, and no
    // restaurants rail.
    expect(find.byType(CategoryCard), findsNWidgets(4));
    expect(find.byType(ServiceGridCard), findsNWidgets(4));
    expect(find.text('Рестораны'), findsNothing);
  });

  testWidgets('a category opens the catalog filtered to it', (tester) async {
    await pumpHome(tester);
    await tapVisible(tester, find.byType(CategoryCard).at(1));
    expect(catalog(tester).initialCategorySlug, 'hosts');
  });

  testWidgets('«Все услуги» opens the full catalog, Back returns to Home '
      'where it was', (tester) async {
    await pumpHome(tester, size: const Size(390, 800));
    final all = find.byKey(const ValueKey('home-all-services'));
    await tester.scrollUntilVisible(
      all,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(all).dy;
    await tester.tap(all);
    await tester.pumpAndSettle();
    expect(catalog(tester).initialCategorySlug, isNull);

    await tester.binding.handlePopRoute(); // system Back
    await tester.pumpAndSettle();
    expect(find.byType(ServicesScreen), findsNothing);
    expect(tester.getTopLeft(all).dy, before);
  });

  testWidgets('«Популярное» → «Все» opens the full catalog', (tester) async {
    await pumpHome(tester);
    await tapVisible(tester, find.byKey(const ValueKey('home-popular-all')));
    expect(catalog(tester).initialCategorySlug, isNull);
  });

  testWidgets('a popular card opens that service', (tester) async {
    await pumpHome(tester);
    // All rated the same here, so the newest come first.
    await tapVisible(tester, find.byKey(const ValueKey('home-popular-10')));
    expect(
      tester
          .widget<ServiceDetailScreen>(find.byType(ServiceDetailScreen))
          .listingId,
      10,
    );
  });

  group('no overflow', () {
    final themes = <(String, ThemeData Function())>[
      ('light', () => AppTheme.light),
      ('dark', () => AppTheme.dark),
    ];
    for (final theme in themes) {
      for (final width in [320.0, 390.0, 430.0]) {
        for (final locale in AppLocale.values) {
          for (final scale in [1.0, 1.3]) {
            testWidgets(
              '${theme.$1} · ${width.toInt()} · ${locale.name} · ×$scale',
              (tester) async {
                await pumpHome(
                  tester,
                  size: Size(width, 4000),
                  theme: theme.$2,
                  locale: locale,
                  textScale: scale,
                );
                expect(find.byType(ServiceGridCard), findsNWidgets(4));
                expect(tester.takeException(), isNull);
              },
            );
          }
        }
      }
    }
  });
}
