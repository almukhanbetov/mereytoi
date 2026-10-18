import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/models/category.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/models/site_statistics.dart';
import 'package:mereytoi_app/screens/root_shell.dart';
import 'package:mereytoi_app/state/categories_provider.dart';
import 'package:mereytoi_app/state/listings_provider.dart';
import 'package:mereytoi_app/state/providers.dart';
import 'package:mereytoi_app/state/statistics_provider.dart';
import 'package:mereytoi_app/widgets/app_bottom_nav.dart';
import 'package:mereytoi_app/widgets/chat/chat_fab.dart';
import 'package:mereytoi_app/widgets/service_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/city_fake_api.dart';

/// Same empty in-memory secure storage the other RootShell tests use —
/// Home's account button restores a session on construction.
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

Listing _listing(int id) => Listing(
  id: id,
  categoryId: 1,
  category: const Category(
    id: 1,
    slug: 'hosts',
    nameRu: 'Ведущие',
    nameKz: 'Жүргізушілер',
    position: 0,
  ),
  nameRu: 'Ведущий $id',
  nameKz: 'Жүргізуші $id',
  descriptionRu: '',
  descriptionKz: '',
  city: 'Алматы',
  phone: '',
  price: 250000,
  minGuests: 0,
  maxGuests: 0,
  rating: 4.8,
  emoji: '',
  colorFrom: '',
  colorTo: '',
  imageUrls: const [],
  isActive: true,
);

void main() {
  setUp(() {
    FlutterSecureStoragePlatform.instance = _EmptySecureStoragePlatform();
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpShell(
    WidgetTester tester, {
    required Size size,
    required ThemeData Function() theme,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (client, _) = fakeCityApi();
    final listings = List.generate(12, (i) => _listing(i + 1));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(client),
          categoriesProvider.overrideWith(
            (ref) => Future.value(const <Category>[]),
          ),
          listingsProvider(null).overrideWith((ref) => Future.value(listings)),
          listingsProvider(
            'venues',
          ).overrideWith((ref) => Future.value(const [])),
          statisticsProvider.overrideWith(
            (ref) => Future.value(
              const SiteStatistics(
                eventsCount: 0,
                happyGuestsCount: 0,
                yearsExperience: 0,
                citiesCount: 0,
              ),
            ),
          ),
        ],
        child: MaterialApp(theme: theme(), home: const RootShell()),
      ),
    );
    await tester.pumpAndSettle();
  }

  final themes = <(String, ThemeData Function())>[
    ('light', () => AppTheme.light),
    ('dark', () => AppTheme.dark),
  ];

  for (final theme in themes) {
    for (final width in [320.0, 393.0]) {
      testWidgets(
        '${theme.$1} · ${width.toInt()}px: floating 52px translucent button, '
        '16 from the right, 28 above the nav; the last card scrolls above it',
        (tester) async {
          await pumpShell(tester, size: Size(width, 800), theme: theme.$2);
          expect(tester.takeException(), isNull);

          final fab = tester.getRect(find.byType(ChatFab));
          final nav = tester.getRect(find.byType(AppBottomNav));

          expect(fab.size, const Size(kChatFabSize, kChatFabSize));
          expect(width - fab.right, 16);
          expect(nav.top - fab.bottom, kChatFabNavGap);
          expect(800 - fab.bottom, inInclusiveRange(80, 88));

          // Floating again: no separate strip, the tab body runs down to
          // the nav and the button overlays it.
          final body = tester.getRect(find.byType(IndexedStack));
          expect(body.bottom, nav.top);

          final material = tester.widget<Material>(
            find.descendant(
              of: find.byType(ChatFab),
              matching: find.byType(Material),
            ),
          );
          expect(material.color!.a, closeTo(kChatFabOpacity, 0.01));

          // Services: a long list scrolled to the very end — the last card
          // ends above the button, so nothing stays hidden under it.
          await tester.tap(
            find.descendant(
              of: find.byType(AppBottomNav),
              matching: find.text('Услуги'),
            ),
          );
          await tester.pumpAndSettle();
          final lastCard = find.text('Ведущий 12');
          await tester.dragUntilVisible(
            lastCard,
            find.byType(CustomScrollView),
            const Offset(0, -300),
          );
          await tester.drag(
            find.byType(CustomScrollView),
            const Offset(0, -2000),
          );
          await tester.pumpAndSettle();
          final card = tester.getRect(
            find.ancestor(of: lastCard, matching: find.byType(ServiceListTile)),
          );
          expect(card.bottom, lessThanOrEqualTo(fab.top));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('no chat button on the Корзина tab; back on the others', (
    tester,
  ) async {
    await pumpShell(
      tester,
      size: const Size(393, 800),
      theme: () => AppTheme.light,
    );
    expect(find.byType(ChatFab), findsOneWidget);

    Finder tab(String label) => find.descendant(
      of: find.byType(AppBottomNav),
      matching: find.text(label),
    );
    await tester.tap(tab('Корзина'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatFab), findsNothing);

    await tester.tap(tab('Мой той'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatFab), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('hide on scroll', () {
    bool fabShown(WidgetTester tester) {
      final opacity = tester.widget<AnimatedOpacity>(
        find.descendant(
          of: find.byType(AutoHideChatFab),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      final ignore = tester.widget<IgnorePointer>(
        find.descendant(
          of: find.byType(AutoHideChatFab),
          matching: find.byType(IgnorePointer),
        ),
      );
      expect(ignore.ignoring, opacity.opacity == 0);
      return opacity.opacity == 1;
    }

    Future<void> openServices(WidgetTester tester) async {
      await pumpShell(
        tester,
        size: const Size(393, 800),
        theme: () => AppTheme.light,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AppBottomNav),
          matching: find.text('Услуги'),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('Услуги at the very top: hidden (its first card is there)', (
      tester,
    ) async {
      await openServices(tester);
      await tester.pump(kChatFabAnimationDuration);
      expect(fabShown(tester), isFalse);
    });

    testWidgets('Главная at the very top: shown (main chat entry point)', (
      tester,
    ) async {
      await pumpShell(
        tester,
        size: const Size(393, 800),
        theme: () => AppTheme.light,
      );
      expect(fabShown(tester), isTrue);
    });

    testWidgets('Услуги: back at the very top hides it again', (tester) async {
      await openServices(tester);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.pump(kChatFabReshowDelay);
      await tester.pumpAndSettle();
      expect(fabShown(tester), isTrue);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, 2000));
      await tester.pumpAndSettle();
      await tester.pump(kChatFabReshowDelay);
      await tester.pumpAndSettle();
      expect(fabShown(tester), isFalse);
    });

    testWidgets('Услуги remembers its position across tab switches', (
      tester,
    ) async {
      await openServices(tester);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();

      Finder tab(String label) => find.descendant(
        of: find.byType(AppBottomNav),
        matching: find.text(label),
      );
      await tester.tap(tab('Главная'));
      await tester.pumpAndSettle();
      expect(fabShown(tester), isTrue);
      await tester.tap(tab('Услуги'));
      await tester.pumpAndSettle();
      // Still scrolled below the top → shown.
      expect(fabShown(tester), isTrue);
    });

    testWidgets(
      'hides while scrolling down, comes back ~600ms after scrolling stops',
      (tester) async {
        await openServices(tester);
        final gesture = await tester.startGesture(const Offset(200, 500));
        for (var i = 0; i < 5; i++) {
          await gesture.moveBy(const Offset(0, -40));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pump(kChatFabAnimationDuration);
        expect(fabShown(tester), isFalse);

        // Finger still down: stays hidden.
        await tester.pump(const Duration(seconds: 1));
        expect(fabShown(tester), isFalse);

        await gesture.up();
        await tester.pumpAndSettle();
        // Not before the delay...
        expect(fabShown(tester), isFalse);
        // ...but after it.
        await tester.pump(kChatFabReshowDelay);
        await tester.pumpAndSettle();
        expect(fabShown(tester), isTrue);
      },
    );

    testWidgets('scrolling back up shows it right away', (tester) async {
      await openServices(tester);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pump(kChatFabAnimationDuration);
      expect(fabShown(tester), isFalse);

      final gesture = await tester.startGesture(const Offset(200, 400));
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(0, 30));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(kChatFabAnimationDuration);
      expect(fabShown(tester), isTrue);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a tab switch shows it again', (tester) async {
      await openServices(tester);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pump(kChatFabAnimationDuration);
      expect(fabShown(tester), isFalse);

      await tester.tap(
        find.descendant(
          of: find.byType(AppBottomNav),
          matching: find.text('Главная'),
        ),
      );
      await tester.pump();
      await tester.pump(kChatFabAnimationDuration);
      expect(fabShown(tester), isTrue);
      await tester.pumpAndSettle();
    });

    testWidgets('horizontal scrolling (Home carousels) never hides it', (
      tester,
    ) async {
      await pumpShell(
        tester,
        size: const Size(393, 800),
        theme: () => AppTheme.light,
      );
      // The carousels sit below the provider promo card.
      await tester.scrollUntilVisible(
        find.text('Популярные услуги'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final carousel = find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
      );
      expect(carousel, findsWidgets);
      await tester.ensureVisible(carousel.first);
      await tester.pumpAndSettle();
      await tester.drag(carousel.first, const Offset(-300, 0));
      await tester.pump(kChatFabAnimationDuration);
      expect(fabShown(tester), isTrue);
      await tester.pumpAndSettle();
    });
  });

  test('scroll views end far enough below the button', () {
    expect(kChatFabClearance, kChatFabNavGap + kChatFabSize + 16);
  });
}
