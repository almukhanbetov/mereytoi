import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/storage/locale_storage.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/models/cart_item.dart';
import 'package:mereytoi_app/models/category.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/models/site_statistics.dart';
import 'package:mereytoi_app/screens/home/home_screen.dart';
import 'package:mereytoi_app/state/auth_provider.dart';
import 'package:mereytoi_app/state/cart_provider.dart';
import 'package:mereytoi_app/state/categories_provider.dart';
import 'package:mereytoi_app/state/listings_provider.dart';
import 'package:mereytoi_app/state/locale_provider.dart';
import 'package:mereytoi_app/state/statistics_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Этап 10Б-А3 — the language toggle used to show the current language as
/// short text ("РУС"/"ҚАЗ"/"ENG"); on the real device that reportedly
/// rendered as garbled/CJK-looking glyphs and didn't visually update after
/// switching. It's now a constant `Icons.language_rounded` glyph (same
/// 44×44 circle shape as the theme toggle) that opens the same
/// [LocaleSheet] — the icon itself never changes; only the sheet's own
/// checkmark and this button's `Semantics.label` (for a screen reader) do.
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

Widget _wrap(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(theme: AppTheme.dark, home: const HomeScreen()),
  );
}

ProviderContainer _homeContainer() {
  return ProviderContainer(
    overrides: [
      categoriesProvider.overrideWith(
        (ref) => Future.value(const <Category>[]),
      ),
      listingsProvider(null).overrideWith((ref) => Future.value(const [])),
      listingsProvider('venues').overrideWith((ref) => Future.value(const [])),
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
  );
}

Future<void> _openLocaleSheet(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.language_rounded));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    FlutterSecureStoragePlatform.instance = _EmptySecureStoragePlatform();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'the trigger shows a language icon, never text like "РУС"/"ҚАЗ"/"ENG"',
    (tester) async {
      final container = _homeContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_wrap(container));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.language_rounded), findsOneWidget);
      expect(find.text('РУС'), findsNothing);
      expect(find.text('ҚАЗ'), findsNothing);
      expect(find.text('ENG'), findsNothing);
    },
  );

  testWidgets(
    'tapping the icon opens a sheet listing all three languages by their own native name',
    (tester) async {
      final container = _homeContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_wrap(container));
      await tester.pumpAndSettle();

      await _openLocaleSheet(tester);

      expect(find.text('Русский'), findsOneWidget);
      expect(find.text('Қазақша'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      // No Chinese/decorative glyphs anywhere near the language names —
      // grep the rendered text nodes for anything outside the expected
      // three scripts would be excessive here; the concrete symptom
      // reported was specifically the trigger's own short-text label,
      // already covered by the previous test.
    },
  );

  testWidgets(
    'the selected-radio indicator tracks the selected language while the trigger icon itself never changes',
    (tester) async {
      final container = _homeContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_wrap(container));
      await tester.pumpAndSettle();

      await _openLocaleSheet(tester);
      await tester.tap(find.text('Қазақша'));
      await tester.pumpAndSettle();

      expect(container.read(localeProvider), AppLocale.kz);
      // Still exactly one language icon in the app bar — same glyph,
      // regardless of which language is now active.
      expect(find.byIcon(Icons.language_rounded), findsOneWidget);

      await _openLocaleSheet(tester);
      // Exactly one row shows the "checked" radio glyph (Қазақша); the
      // other two rows fall back to the plain unchecked radio outline.
      expect(find.byIcon(Icons.radio_button_checked_rounded), findsOneWidget);
      expect(
        find.byIcon(Icons.radio_button_unchecked_rounded),
        findsNWidgets(2),
      );
    },
  );

  testWidgets(
    'switching Русский → Қазақша → English persists through localeProvider',
    (tester) async {
      final container = _homeContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_wrap(container));
      await tester.pumpAndSettle();

      await _openLocaleSheet(tester);
      await tester.tap(find.text('Қазақша'));
      await tester.pumpAndSettle();
      expect(container.read(localeProvider), AppLocale.kz);

      await _openLocaleSheet(tester);
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(container.read(localeProvider), AppLocale.en);

      await _openLocaleSheet(tester);
      await tester.tap(find.text('Русский'));
      await tester.pumpAndSettle();
      expect(container.read(localeProvider), AppLocale.ru);
    },
  );

  testWidgets(
    'the screen-reader label reflects the current language even though the icon does not',
    (tester) async {
      final handle = tester.ensureSemantics();
      final container = _homeContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_wrap(container));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Язык интерфейса: Русский'), findsOneWidget);

      await _openLocaleSheet(tester);
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel('Interface language: English'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testWidgets('the language icon is reachable by a guest, no login required', (
    tester,
  ) async {
    final container = _homeContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    expect(container.read(authProvider), isA<AuthUnauthenticated>());
    expect(find.byIcon(Icons.language_rounded), findsOneWidget);

    await _openLocaleSheet(tester);
    expect(find.text('Русский'), findsOneWidget);
  });

  test(
    't() falls back to the ru: string under AppLocale.en when no en: was given — never blank, never throws',
    () {
      expect(
        t(AppLocale.en, ru: 'Только по-русски', kz: 'Тек қазақша'),
        'Только по-русски',
      );
    },
  );

  for (final width in [320.0, 360.0, 393.0]) {
    testWidgets(
      'the app bar (theme + language + notifications + account icons) does not overflow at ${width.toInt()}dp',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final container = _homeContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(_wrap(container));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byIcon(Icons.language_rounded), findsOneWidget);
        expect(find.byIcon(Icons.brightness_auto_rounded), findsOneWidget);
        expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
      },
    );
  }

  // Этап 10Б-А5 — real interface translation, not just the picker's own
  // labels: the Home screen's actual section copy must change with it.
  testWidgets(
    'Home screen copy actually translates: RU → KZ → EN → RU, each with its own correct wording',
    (tester) async {
      final container = _homeContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_wrap(container));
      await tester.pumpAndSettle();

      // ru (default) — anchored on the hero CTA button, which sits above
      // the fold and renders unconditionally (unlike the listing
      // carousels, which hide themselves entirely when their data is an
      // empty list — exactly what this test's stubbed providers return —
      // and unlike the "Услуги" section further down, which a plain
      // `find.text` can't see until it's scrolled into the sliver
      // viewport's build extent).
      expect(find.text('Смотреть услуги'), findsOneWidget);

      await _openLocaleSheet(tester);
      await tester.tap(find.text('Қазақша'));
      await tester.pumpAndSettle();
      expect(find.text('Қызметтерді қарау'), findsOneWidget);
      expect(find.text('Смотреть услуги'), findsNothing);

      await _openLocaleSheet(tester);
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(find.text('View services'), findsOneWidget);
      expect(find.text('Қызметтерді қарау'), findsNothing);

      await _openLocaleSheet(tester);
      await tester.tap(find.text('Русский'));
      await tester.pumpAndSettle();
      expect(find.text('Смотреть услуги'), findsOneWidget);
    },
  );

  testWidgets(
    'the selected language persists to LocaleStorage and survives a simulated restart',
    (tester) async {
      final container = _homeContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_wrap(container));
      await tester.pumpAndSettle();

      await _openLocaleSheet(tester);
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      await container.read(localeProvider.notifier).debugPersisted;

      expect(await LocaleStorage.instance.read(), AppLocale.en);

      final restarted = _homeContainer();
      addTearDown(restarted.dispose);
      await restarted.read(localeProvider.notifier).ready;

      await tester.pumpWidget(_wrap(restarted));
      await tester.pumpAndSettle();

      expect(find.text('View services'), findsOneWidget);
    },
  );

  testWidgets('switching language from Home never resets the cart', (
    tester,
  ) async {
    final container = _homeContainer();
    addTearDown(container.dispose);
    await container.read(cartProvider.notifier).ready;
    container
        .read(cartProvider.notifier)
        .addItem(
          CartItem.fromListing(
            const Listing(
              id: 7,
              categoryId: 1,
              nameRu: 'Тестовая услуга',
              nameKz: 'Тестовая услуга',
              descriptionRu: '',
              descriptionKz: '',
              city: '',
              phone: '',
              price: 5000,
              minGuests: 0,
              maxGuests: 0,
              rating: 0,
              emoji: '',
              colorFrom: '',
              colorTo: '',
              imageUrls: [],
              isActive: true,
            ),
            name: 'Тестовая услуга',
            categoryLabel: 'Тест',
          ),
        );

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    await _openLocaleSheet(tester);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(container.read(cartProvider), hasLength(1));
    expect(container.read(cartProvider).single.name, 'Тестовая услуга');
  });

  testWidgets(
    'no app-bar overflow at 320dp with Kazakh selected (its labels tend to run longest)',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = _homeContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_wrap(container));
      await tester.pumpAndSettle();

      await _openLocaleSheet(tester);
      await tester.tap(find.text('Қазақша'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.language_rounded), findsOneWidget);
    },
  );

  testWidgets('Kazakh-specific letters (Қ/Ұ/Ө/Ғ/Ң) render without throwing', (
    tester,
  ) async {
    final container = _homeContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    await _openLocaleSheet(tester);
    await tester.tap(find.text('Қазақша'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // The hero CTA's Kazakh wording ("Қызметтерді қарау") carries the
    // Kazakh-only letter қ, which doesn't exist in the Russian alphabet.
    expect(find.text('Қызметтерді қарау'), findsOneWidget);
  });
}
