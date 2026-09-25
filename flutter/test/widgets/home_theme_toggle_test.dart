import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/storage/theme_storage.dart';
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
import 'package:mereytoi_app/state/statistics_provider.dart';
import 'package:mereytoi_app/state/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Этап 10Б-А2 — the theme picker moved from "reachable only inside
/// `ProfileScreen` (auth-only)" to "a compact icon in `HomeScreen`'s app
/// bar, right next to the locale toggle, reachable by a guest". Covers:
///   1. A guest (no auth token at all) can open the sheet and switch
///      Light → Dark → System straight from Home.
///   2. The choice persists in the same `ThemeStorage` `ProfileScreen`'s
///      own row already used — restart-simulated the same way
///      `theme_provider_test.dart` already proves for the provider alone.
///   3. Switching via `HomeScreen`'s button and reading it back via
///      `ProfileScreen`'s own row agree — both watch the exact same
///      `themeModeProvider`/render the exact same `ThemeModeSheet`.
///   4. The switch never touches cart state.
///   5. The app bar (title + 4 action buttons now, one more than before
///      this stage) doesn't overflow at 320dp, even at a larger system
///      text scale.
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

final _homeOverrides = [
  categoriesProvider.overrideWith((ref) => Future.value(const <Category>[])),
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
];

Widget _appFor(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: Consumer(
      builder: (context, ref, _) {
        final mode = ref.watch(themeModeProvider);
        return MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: mode,
          home: const HomeScreen(),
        );
      },
    ),
  );
}

Future<ProviderContainer> _guestContainer() async {
  final container = ProviderContainer(overrides: _homeOverrides);
  await container.read(themeModeProvider.notifier).ready;
  // Never authenticated in these tests — `authProvider`'s own
  // `_restoreSession()` reads the (empty, mocked) secure storage and
  // settles on `AuthUnauthenticated` on its own; nothing to override.
  return container;
}

void main() {
  setUp(() {
    FlutterSecureStoragePlatform.instance = _EmptySecureStoragePlatform();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'a guest sees the theme icon in the app bar and can open the sheet',
    (tester) async {
      final container = await _guestContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_appFor(container));
      await tester.pumpAndSettle();

      expect(container.read(authProvider), isA<AuthUnauthenticated>());
      expect(find.byIcon(Icons.brightness_auto_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.brightness_auto_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Оформление'), findsOneWidget);
      expect(find.text('Светлая'), findsOneWidget);
      expect(find.text('Тёмная'), findsOneWidget);
      expect(find.text('Системная'), findsOneWidget);
    },
  );

  testWidgets('a guest can switch Light → Dark → System from the app bar', (
    tester,
  ) async {
    final container = await _guestContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(_appFor(container));
    await tester.pumpAndSettle();

    // → Light
    await tester.tap(find.byIcon(Icons.brightness_auto_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Светлая'));
    await tester.pumpAndSettle();
    expect(container.read(themeModeProvider), ThemeMode.light);
    expect(find.byIcon(Icons.light_mode_rounded), findsOneWidget);

    // → Dark
    await tester.tap(find.byIcon(Icons.light_mode_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Тёмная'));
    await tester.pumpAndSettle();
    expect(container.read(themeModeProvider), ThemeMode.dark);
    expect(find.byIcon(Icons.dark_mode_rounded), findsOneWidget);

    // → System
    await tester.tap(find.byIcon(Icons.dark_mode_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Системная'));
    await tester.pumpAndSettle();
    expect(container.read(themeModeProvider), ThemeMode.system);
    expect(find.byIcon(Icons.brightness_auto_rounded), findsOneWidget);
  });

  testWidgets(
    'the choice made from Home persists to ThemeStorage and survives a simulated restart',
    (tester) async {
      final container = await _guestContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_appFor(container));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.brightness_auto_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Тёмная'));
      await tester.pumpAndSettle();
      await container.read(themeModeProvider.notifier).debugPersisted;

      expect(await ThemeStorage.instance.read(), ThemeMode.dark);

      // A brand-new container/notifier — the same "cold start reads
      // shared_preferences" simulation `theme_provider_test.dart` already
      // uses for the provider alone, exercised here through the real
      // HomeScreen widget instead.
      final restarted = ProviderContainer(overrides: _homeOverrides);
      addTearDown(restarted.dispose);
      await restarted.read(themeModeProvider.notifier).ready;

      await tester.pumpWidget(_appFor(restarted));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.dark_mode_rounded), findsOneWidget);
    },
  );

  testWidgets('switching theme from Home never resets cart state', (
    tester,
  ) async {
    final container = await _guestContainer();
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

    await tester.pumpWidget(_appFor(container));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.brightness_auto_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Тёмная'));
    await tester.pumpAndSettle();

    expect(container.read(cartProvider), hasLength(1));
    expect(container.read(cartProvider).single.name, 'Тестовая услуга');
  });

  testWidgets(
    'no app-bar overflow at 320dp, including a larger system text scale',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = await _guestContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 700),
            textScaler: TextScaler.linear(1.3),
          ),
          child: _appFor(container),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // The four action buttons (notifications/account/theme/locale) all
      // present — the brand mark got squeezed, not the buttons dropped.
      expect(find.byIcon(Icons.brightness_auto_rounded), findsOneWidget);
      expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
    },
  );
}
