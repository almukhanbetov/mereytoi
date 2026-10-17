import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/models/category.dart';
import 'package:mereytoi_app/models/city.dart';
import 'package:mereytoi_app/models/site_statistics.dart';
import 'package:mereytoi_app/screens/home/home_screen.dart';
import 'package:mereytoi_app/screens/services/services_screen.dart';
import 'package:mereytoi_app/state/categories_provider.dart';
import 'package:mereytoi_app/state/city_provider.dart';
import 'package:mereytoi_app/state/locale_provider.dart';
import 'package:mereytoi_app/state/providers.dart';
import 'package:mereytoi_app/state/statistics_provider.dart';
import 'package:mereytoi_app/widgets/city_selector.dart';
import 'package:mereytoi_app/widgets/services/services_city_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/city_fake_api.dart';

/// Same empty in-memory secure storage home_screen_overflow_test.dart uses
/// — HomeScreen's account button restores a session on construction.
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

void main() {
  void setScreen(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<CityFakeAdapter> pumpPill(
    WidgetTester tester, {
    Size size = const Size(390, 800),
    ThemeData? theme,
    AppLocale locale = AppLocale.ru,
    Map<String, Object> prefs = const {},
    List<Override> extraOverrides = const [],
  }) async {
    SharedPreferences.setMockInitialValues({
      ...prefs,
      if (locale != AppLocale.ru) 'app_locale_v1': locale.name,
    });
    setScreen(tester, size);
    final (client, adapter) = fakeCityApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(client),
          ...extraOverrides,
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.dark,
          home: const Scaffold(
            body: SafeArea(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: CitySelectorButton(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return adapter;
  }

  Finder pill() => find.byType(CitySelectorButton);
  Finder inSheet(Finder f) =>
      find.descendant(of: find.byType(CitySheet), matching: f);
  Finder sheetSearch() => inSheet(find.byType(TextField));

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(pill());
    await tester.pumpAndSettle();
    expect(find.byType(CitySheet), findsOneWidget);
  }

  /// The row (tile) whose label is [label] currently shows the checkmark.
  bool isChecked(String label) {
    final check = find.byKey(const ValueKey('city-selected-check'));
    final rows = find.ancestor(of: check, matching: find.byType(Row));
    return find
        .descendant(of: rows.first, matching: find.text(label))
        .evaluate()
        .isNotEmpty;
  }

  testWidgets('13. shows «Все города» initially', (tester) async {
    await pumpPill(tester);
    expect(
      find.descendant(of: pill(), matching: find.text('Все города')),
      findsOneWidget,
    );
    expect(tester.getSemantics(pill()).label, 'Город: Все города. Изменить');
  });

  testWidgets(
    'sheet: handle/title/search, «Все города» first, cities from the API, checkmark on current',
    (tester) async {
      final adapter = await pumpPill(tester);
      await openSheet(tester);

      expect(inSheet(find.text('Выберите город')), findsOneWidget);
      expect(sheetSearch(), findsOneWidget);
      expect(inSheet(find.text('Поиск города')), findsOneWidget);
      for (final c in testCities) {
        expect(inSheet(find.text(c.nameRu)), findsOneWidget);
      }
      final allY = tester.getTopLeft(inSheet(find.text('Все города'))).dy;
      final almatyY = tester.getTopLeft(inSheet(find.text('Алматы'))).dy;
      expect(allY, lessThan(almatyY));
      expect(isChecked('Все города'), isTrue);
      expect(find.byKey(const ValueKey('city-selected-check')), findsOneWidget);

      // Re-opening the sheet never re-requests the list.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await openSheet(tester);
      expect(adapter.requests.where((r) => r.path == '/api/cities').length, 1);
    },
  );

  testWidgets(
    '14/15. selecting Алматы closes the sheet, updates the label, persists, and checks it',
    (tester) async {
      await pumpPill(tester);
      await openSheet(tester);

      await tester.tap(inSheet(find.text('Алматы')));
      await tester.pumpAndSettle();

      expect(find.byType(CitySheet), findsNothing);
      expect(
        find.descendant(of: pill(), matching: find.text('Алматы')),
        findsOneWidget,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('selected_city_id'), 1);

      await openSheet(tester);
      expect(isChecked('Алматы'), isTrue);
      expect(find.byKey(const ValueKey('city-selected-check')), findsOneWidget);

      // Change several times: Астана, then back to Все города.
      await tester.tap(inSheet(find.text('Астана')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: pill(), matching: find.text('Астана')),
        findsOneWidget,
      );
      expect(prefs.getInt('selected_city_id'), 2);

      await openSheet(tester);
      await tester.tap(inSheet(find.text('Все города')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: pill(), matching: find.text('Все города')),
        findsOneWidget,
      );
      expect(prefs.containsKey('selected_city_id'), isFalse);
    },
  );

  testWidgets('restores the saved city after a restart', (tester) async {
    await pumpPill(tester, prefs: {'selected_city_id': 15});
    expect(
      find.descendant(of: pill(), matching: find.text('Туркестан')),
      findsOneWidget,
    );
  });

  testWidgets(
    'an unknown saved id falls back to «Все города» once the list loads',
    (tester) async {
      await pumpPill(tester, prefs: {'selected_city_id': 99});
      expect(
        find.descendant(of: pill(), matching: find.text('Все города')),
        findsOneWidget,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('selected_city_id'), isFalse);
    },
  );

  group('search', () {
    testWidgets('16. RU', (tester) async {
      await pumpPill(tester);
      await openSheet(tester);
      await tester.enterText(sheetSearch(), 'аст');
      await tester.pump();
      expect(inSheet(find.text('Астана')), findsOneWidget);
      expect(inSheet(find.text('Алматы')), findsNothing);
      // «Все города» is a reset, not a result.
      expect(inSheet(find.text('Все города')), findsNothing);

      await tester.enterText(sheetSearch(), 'АЛМ');
      await tester.pump();
      expect(inSheet(find.text('Алматы')), findsOneWidget);
      expect(inSheet(find.text('Астана')), findsNothing);
    });

    testWidgets('17. KZ name from the RU interface', (tester) async {
      await pumpPill(tester);
      await openSheet(tester);
      await tester.enterText(sheetSearch(), 'өске');
      await tester.pump();
      expect(inSheet(find.text('Усть-Каменогорск')), findsOneWidget);
      expect(inSheet(find.text('Алматы')), findsNothing);
    });

    testWidgets('18. EN name', (tester) async {
      await pumpPill(tester);
      await openSheet(tester);
      await tester.enterText(sheetSearch(), 'karag');
      await tester.pump();
      expect(inSheet(find.text('Караганда')), findsOneWidget);
      expect(inSheet(find.text('Астана')), findsNothing);
    });

    testWidgets('19. no results', (tester) async {
      await pumpPill(tester);
      await openSheet(tester);
      await tester.enterText(sheetSearch(), 'zzz');
      await tester.pump();
      expect(inSheet(find.text('Ничего не найдено')), findsOneWidget);
      for (final c in testCities) {
        expect(inSheet(find.text(c.nameRu)), findsNothing);
      }
    });

    testWidgets('search sends no request per keystroke', (tester) async {
      final adapter = await pumpPill(tester);
      await openSheet(tester);
      for (final q in ['а', 'ал', 'алм']) {
        await tester.enterText(sheetSearch(), q);
        await tester.pump();
      }
      expect(adapter.requests.length, 1); // the initial GET /api/cities
    });

    testWidgets('keyboard open: results stay visible above it, no overflow', (
      tester,
    ) async {
      await pumpPill(tester, size: const Size(320, 640));
      await openSheet(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.enterText(sheetSearch(), 'аст');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final astana = tester.getRect(inSheet(find.text('Астана')));
      expect(astana.bottom, lessThan(640 - 300));
    });
  });

  group('loading / error', () {
    testWidgets('loading shows a spinner, «Все города» still selectable', (
      tester,
    ) async {
      final pending = Completer<List<City>>();
      SharedPreferences.setMockInitialValues({});
      setScreen(tester, const Size(390, 800));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [citiesProvider.overrideWith((ref) => pending.future)],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const Scaffold(body: Center(child: CitySelectorButton())),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(pill());
      await tester.pump(const Duration(milliseconds: 400));
      expect(inSheet(find.byType(CircularProgressIndicator)), findsOneWidget);
      expect(inSheet(find.text('Все города')), findsOneWidget);
      pending.complete(testCities);
      await tester.pumpAndSettle();
      expect(inSheet(find.text('Алматы')), findsOneWidget);
    });

    testWidgets('error shows a message and retry refetches', (tester) async {
      var attempts = 0;
      await pumpPill(
        tester,
        extraOverrides: [
          citiesProvider.overrideWith((ref) {
            attempts++;
            if (attempts == 1) return Future.error(Exception('offline'));
            return Future.value(testCities);
          }),
        ],
      );
      await openSheet(tester);
      expect(inSheet(find.text('Повторить')), findsOneWidget);
      expect(inSheet(find.text('Алматы')), findsNothing);

      await tester.tap(inSheet(find.text('Повторить')));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(inSheet(find.text('Алматы')), findsOneWidget);
    });
  });

  group('20–25. themes × widths × locales, no overflow', () {
    const texts = {
      AppLocale.ru: (
        'Все города',
        'Выберите город',
        'Поиск города',
        'Ничего не найдено',
        'Усть-Каменогорск',
      ),
      AppLocale.kz: (
        'Барлық қалалар',
        'Қаланы таңдаңыз',
        'Қаланы іздеу',
        'Ештеңе табылмады',
        'Өскемен',
      ),
      AppLocale.en: (
        'All cities',
        'Select city',
        'Search city',
        'Nothing found',
        'Oskemen',
      ),
    };
    // Getters, not ThemeData values: building a theme outside a test zone
    // trips google_fonts' runtime loader.
    final themes = <(String, ThemeData Function())>[
      ('dark', () => AppTheme.dark),
      ('light', () => AppTheme.light),
    ];
    for (final theme in themes) {
      for (final width in [320.0, 390.0]) {
        for (final locale in AppLocale.values) {
          testWidgets('${theme.$1} · ${width.toInt()}px · ${locale.name}', (
            tester,
          ) async {
            final (all, title, hint, empty, longCity) = texts[locale]!;
            await pumpPill(
              tester,
              size: Size(width, 700),
              theme: theme.$2(),
              locale: locale,
              prefs: {'selected_city_id': 8}, // longest name
            );
            expect(tester.takeException(), isNull);
            expect(
              find.descendant(of: pill(), matching: find.text(longCity)),
              findsOneWidget,
            );

            await openSheet(tester);
            expect(tester.takeException(), isNull);
            expect(inSheet(find.text(title)), findsOneWidget);
            expect(inSheet(find.text(hint)), findsOneWidget);
            expect(inSheet(find.text(all)), findsOneWidget);
            expect(isChecked(longCity), isTrue);

            await tester.enterText(sheetSearch(), 'zzz');
            await tester.pump();
            expect(inSheet(find.text(empty)), findsOneWidget);
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });

  testWidgets(
    'ServicesScreen: changing city keeps the category tile and search text',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      setScreen(tester, const Size(390, 800));
      final (client, adapter) = fakeCityApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            categoriesProvider.overrideWith(
              (ref) => Future.value(const [
                Category(
                  id: 1,
                  slug: 'venues',
                  nameRu: 'Рестораны',
                  nameKz: 'Мейрамханалар',
                  position: 0,
                ),
              ]),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const ServicesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(adapter.listingRequests.last.queryParameters, isEmpty);

      await tester.tap(find.text('Рестораны'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'той');
      await tester.pump(const Duration(milliseconds: 400));
      expect(adapter.listingRequests.last.queryParameters, {
        'category': 'venues',
      });

      await tester.tap(find.byType(ServicesCitySelector));
      await tester.pumpAndSettle();
      await tester.tap(inSheet(find.text('Астана')));
      await tester.pumpAndSettle();

      expect(adapter.listingRequests.last.queryParameters, {
        'category': 'venues',
        'city_id': 2,
      });
      expect(find.text('той'), findsOneWidget); // search text kept
      expect(tester.takeException(), isNull);

      await tester.tap(find.byType(ServicesCitySelector));
      await tester.pumpAndSettle();
      await tester.tap(inSheet(find.text('Все города')));
      await tester.pumpAndSettle();
      expect(adapter.listingRequests.last.queryParameters, {
        'category': 'venues',
      });
    },
  );

  for (final width in [320.0, 390.0]) {
    testWidgets(
      'HomeScreen at ${width.toInt()}px: pill under the app bar, city change refetches both rails',
      (tester) async {
        FlutterSecureStoragePlatform.instance = _EmptySecureStoragePlatform();
        SharedPreferences.setMockInitialValues({});
        setScreen(tester, Size(width, 800));
        final (client, adapter) = fakeCityApi();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(client),
              categoriesProvider.overrideWith(
                (ref) => Future.value(const <Category>[]),
              ),
              statisticsProvider.overrideWith(
                (ref) => Future.value(
                  const SiteStatistics(
                    eventsCount: 1,
                    happyGuestsCount: 1,
                    yearsExperience: 1,
                    citiesCount: 1,
                  ),
                ),
              ),
            ],
            child: MaterialApp(theme: AppTheme.dark, home: const HomeScreen()),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(pill(), findsOneWidget);
        expect(
          find.descendant(of: pill(), matching: find.text('Все города')),
          findsOneWidget,
        );
        expect(
          adapter.listingRequests.map((r) => r.queryParameters),
          containsAll([
            <String, dynamic>{},
            {'category': 'venues'},
          ]),
        );

        await openSheet(tester);
        await tester.tap(inSheet(find.text('Алматы')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final afterChange = adapter.listingRequests
            .skip(2)
            .map((r) => r.queryParameters)
            .toList();
        expect(
          afterChange,
          containsAll([
            {'city_id': 1},
            {'category': 'venues', 'city_id': 1},
          ]),
        );
        expect(afterChange, hasLength(2));
      },
    );
  }
}
