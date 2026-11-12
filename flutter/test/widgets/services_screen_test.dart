import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/models/category.dart';
import 'package:mereytoi_app/screens/services/services_screen.dart';
import 'package:mereytoi_app/state/categories_provider.dart';
import 'package:mereytoi_app/state/locale_provider.dart';
import 'package:mereytoi_app/state/providers.dart';
import 'package:mereytoi_app/widgets/city_selector.dart';
import 'package:mereytoi_app/widgets/services/services_category_grid.dart';
import 'package:mereytoi_app/widgets/services/services_city_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/city_fake_api.dart';

/// The production category set (same slugs and names as GET
/// /api/categories), including the long two-line names.
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
    nameRu: 'Ведущие',
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
  Category(
    id: 7,
    slug: 'Betashar',
    nameRu: 'Беташар',
    nameKz: 'Беташар',
    position: 7,
  ),
  Category(
    id: 8,
    slug: 'Photo and Video',
    nameRu: 'Фото/Видео съемка',
    nameKz: 'Фото/Видео съемка',
    position: 8,
  ),
  Category(
    id: 9,
    slug: 'Interactiveequipment',
    nameRu: 'Интерактивное оборудование',
    nameKz: 'Интерактивті жабдық',
    position: 9,
  ),
];

void main() {
  Future<CityFakeAdapter> pumpServices(
    WidgetTester tester, {
    Size size = const Size(390, 900),
    ThemeData Function()? theme,
    AppLocale locale = AppLocale.ru,
    double textScale = 1,
    String? initialCategorySlug,
  }) async {
    SharedPreferences.setMockInitialValues({
      if (locale != AppLocale.ru) 'app_locale_v1': locale.name,
    });
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (client, adapter) = fakeCityApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(client),
          categoriesProvider.overrideWith((ref) => Future.value(_categories)),
        ],
        child: MaterialApp(
          theme: (theme ?? () => AppTheme.light)(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: ServicesScreen(initialCategorySlug: initialCategorySlug),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return adapter;
  }

  testWidgets('city card shows the «Город» caption and opens the city sheet', (
    tester,
  ) async {
    await pumpServices(tester);
    final card = find.byType(ServicesCitySelector);
    expect(card, findsOneWidget);
    // One compact row: "Город  Все города".
    expect(
      find.descendant(
        of: card,
        matching: find.text('Город  Все города', findRichText: true),
      ),
      findsOneWidget,
    );
    expect(tester.getSize(card).height, inInclusiveRange(52, 60));
    // The old compact pill is Home-only now.
    expect(find.byType(CitySelectorButton), findsNothing);

    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.byType(CitySheet), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(CitySheet),
        matching: find.text('Алматы'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: card,
        matching: find.text('Город  Алматы', findRichText: true),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'category grid: no «Все» tile, collapsed to 6, expands to all 9, collapses',
    (tester) async {
      await pumpServices(tester);
      expect(find.byType(ServicesCategoryTile), findsNWidgets(6));
      expect(find.text('Все'), findsNothing);
      expect(find.text('Показать все'), findsOneWidget);

      // Two columns on a phone: tiles 1 and 2 share a row, tile 3 is below.
      final tiles = find.byType(ServicesCategoryTile);
      final first = tester.getCenter(tiles.at(0));
      final second = tester.getCenter(tiles.at(1));
      final third = tester.getCenter(tiles.at(2));
      expect((first.dy - second.dy).abs(), lessThan(1));
      expect(second.dx, greaterThan(first.dx));
      expect(third.dy, greaterThan(first.dy));

      await tester.ensureVisible(find.text('Показать все'));
      await tester.tap(find.text('Показать все'));
      await tester.pumpAndSettle();
      expect(find.byType(ServicesCategoryTile), findsNWidgets(9));
      expect(find.text('Свернуть'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Свернуть'));
      await tester.pumpAndSettle();
      expect(find.byType(ServicesCategoryTile), findsNWidgets(6));
    },
  );

  // The real phone: 393dp wide with the system font at 1.25.
  testWidgets('Xiaomi size at 1.25× text: tiles stay 76 tall, no overflow', (
    tester,
  ) async {
    await pumpServices(tester, size: const Size(393, 873), textScale: 1.25);
    await tester.ensureVisible(find.byType(TextButton));
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(ServicesCategoryTile).first).height, 76);
    // Tile names cap the system text scale; the rest of the screen doesn't.
    final tileText = find.descendant(
      of: find.widgetWithText(ServicesCategoryTile, 'Ведущие'),
      matching: find.text('Ведущие'),
    );
    expect(
      MediaQuery.textScalerOf(tester.element(tileText)).scale(10),
      closeTo(11, 0.001),
    );
    expect(tester.takeException(), isNull);
  });

  // The test font draws every glyph 1em wide, which makes widths exact:
  // "исполнители" is 11em, i.e. 165/154/143 px at 15/14/13.
  group('servicesTileFontSize', () {
    const style = TextStyle(fontSize: 15, height: 1.25);
    double size(String text, double width) => servicesTileFontSize(
      text,
      style,
      width,
      TextScaler.noScaling,
      TextDirection.ltr,
    );

    test('keeps 15 when every word fits', () {
      expect(size('Артисты и исполнители', 170), 15);
    });
    test('steps down instead of cutting the longest word', () {
      expect(size('Артисты и исполнители', 160), 14);
      expect(size('Артисты и исполнители', 150), 13);
    });
    test('below the steps, shrinks just enough for the longest word', () {
      // "исполнители" is 132 at 12 → fits 120 at 12 × 120/132 ≈ 10.9 → 10.5.
      expect(size('Артисты и исполнители', 120), 10.5);
      // ...but never below 10.
      expect(size('Артисты и исполнители', 60), 10);
    });
    test('hyphen and slash count as break points', () {
      // "Шоу-" + "программы" (9em = 135 at 15) fits; the whole token wouldn't.
      expect(size('Шоу-программы', 140), 15);
      expect(size('Фото/Видео', 100), 15); // "Фото/" + "Видео", 75 each
    });
    test('respects the system text scale', () {
      expect(
        servicesTileFontSize(
          'Артисты и исполнители',
          style,
          170,
          const TextScaler.linear(1.25),
          TextDirection.ltr,
        ),
        12,
      );
    });
  });

  testWidgets('every tile has the same height', (tester) async {
    await pumpServices(tester);
    final heights = tester
        .widgetList<ServicesCategoryTile>(find.byType(ServicesCategoryTile))
        .map((w) => tester.getSize(find.byWidget(w)).height.toStringAsFixed(1))
        .toSet();
    expect(heights, hasLength(1));
    expect(double.parse(heights.single), greaterThanOrEqualTo(64));
  });

  testWidgets('tapping a tile fetches that category on a screen of its own', (
    tester,
  ) async {
    final adapter = await pumpServices(tester);
    expect(adapter.feedRequests.last.queryParameters, {'limit': 20});

    await tester.tap(find.text('Ведущие'));
    await tester.pumpAndSettle();
    expect(adapter.feedRequests.last.queryParameters, {
      'limit': 20,
      'category': 'hosts',
    });
    expect(find.byType(ServicesCategoryTile), findsNothing);
    expect(find.byType(BackButton), findsOneWidget);
  });

  testWidgets('three columns on a wide screen', (tester) async {
    await pumpServices(tester, size: const Size(700, 1000));
    final tiles = find.byType(ServicesCategoryTile);
    final y = [0, 1, 2].map((i) => tester.getCenter(tiles.at(i)).dy);
    expect(y.toSet(), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('search: clear button appears with text and clears it', (
    tester,
  ) async {
    await pumpServices(tester);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
    await tester.enterText(find.byType(TextField), 'той');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.text('той'), findsNothing);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
  });

  group('no overflow', () {
    final themes = <(String, ThemeData Function())>[
      ('light', () => AppTheme.light),
      ('dark', () => AppTheme.dark),
    ];
    for (final theme in themes) {
      for (final width in [320.0, 390.0]) {
        for (final locale in AppLocale.values) {
          testWidgets('${theme.$1} · ${width.toInt()}px · ${locale.name}', (
            tester,
          ) async {
            await pumpServices(
              tester,
              size: Size(width, 900),
              theme: theme.$2,
              locale: locale,
            );
            expect(tester.takeException(), isNull);
            final toggle = find.byType(TextButton);
            await tester.ensureVisible(toggle);
            await tester.tap(toggle);
            await tester.pumpAndSettle();
            expect(find.byType(ServicesCategoryTile), findsNWidgets(9));
            expect(tester.takeException(), isNull);
          });
        }
      }
    }

    testWidgets('320px with 1.3× system text', (tester) async {
      await pumpServices(tester, size: const Size(320, 900), textScale: 1.3);
      expect(tester.takeException(), isNull);
      final toggle = find.byType(TextButton);
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  test('category icons map from irregular slugs, unknown ones fall back', () {
    expect(servicesCategoryIcon(null), Icons.apps_rounded);
    expect(servicesCategoryIcon('venues'), Icons.restaurant_rounded);
    expect(servicesCategoryIcon('Photo and Video'), Icons.photo_camera_rounded);
    expect(servicesCategoryIcon('Betashar'), Icons.favorite_rounded);
    expect(
      servicesCategoryIcon('Interactiveequipment'),
      Icons.videogame_asset_rounded,
    );
    expect(servicesCategoryIcon('something-new'), Icons.auto_awesome_rounded);
  });
}
