import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/app.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/models/cart_item.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/state/cart_provider.dart';
import 'package:mereytoi_app/state/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Этап 10Б-А — status bar + Android navigation bar styling. Covers:
///   1. [AppSystemUiOverlay] itself picks the right style per brightness,
///      independently for each of the two tokens it touches.
///   2. The exact `resolveBrightness` + outer `AnnotatedRegion` wiring
///      `app.dart`'s `MereytoiApp` uses actually applies the right style
///      for Light/Dark/System — reproduced here as a minimal harness
///      rather than pumping the real `MereytoiApp` (its `SplashScreen`
///      starts a real 1400ms navigation `Timer` that `flutter_test` flags
///      as "still pending" once a test tears down before it fires; that
///      timer is unrelated to what this file is actually verifying).
///   3. Switching `themeModeProvider` mid-session updates the resolved
///      style without losing any other provider's state (cart is the
///      stand-in here — brief requirement 10's own "сохранение состояния
///      корзины/калькулятора при смене темы").
Widget _harness() {
  return Consumer(
    builder: (context, ref, _) {
      final themeMode = ref.watch(themeModeProvider);
      final brightness = resolveBrightness(
        themeMode,
        MediaQuery.platformBrightnessOf(context),
      );
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppSystemUiOverlay.forBrightness(brightness),
        child: MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeMode,
          home: const SizedBox.shrink(),
        ),
      );
    },
  );
}

SystemUiOverlayStyle _regionValue(WidgetTester tester) {
  return tester
      .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
      )
      .value;
}

void main() {
  // CartNotifier's storage is backed by shared_preferences — same
  // requirement `cart_provider_test.dart` already documents.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AppSystemUiOverlay.forBrightness', () {
    test('light brightness → dark status/nav icons, light nav bar color', () {
      final style = AppSystemUiOverlay.forBrightness(Brightness.light);

      expect(style.statusBarIconBrightness, Brightness.dark);
      expect(
        style.systemNavigationBarColor,
        MereytoiColors.light.navigationBackground,
      );
      expect(style.systemNavigationBarIconBrightness, Brightness.dark);
    });

    test('dark brightness → light status/nav icons, dark nav bar color', () {
      final style = AppSystemUiOverlay.forBrightness(Brightness.dark);

      expect(style.statusBarIconBrightness, Brightness.light);
      expect(
        style.systemNavigationBarColor,
        MereytoiColors.dark.navigationBackground,
      );
      expect(style.systemNavigationBarIconBrightness, Brightness.light);
    });

    test(
      'light and dark are genuinely distinct at the token level, never a mechanical inversion',
      () {
        // Fails if AppSystemUiOverlay ever gets "simplified" back down to a
        // single shared style, or a Brightness flip that forgets the nav
        // bar color also has to change to the other theme's own token.
        expect(
          AppSystemUiOverlay.light.systemNavigationBarColor,
          isNot(AppSystemUiOverlay.dark.systemNavigationBarColor),
        );
      },
    );
  });

  group('the app-wide AnnotatedRegion tracks themeModeProvider', () {
    testWidgets('ThemeMode.light', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(themeModeProvider.notifier).setMode(ThemeMode.light);

      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: _harness()),
      );

      expect(_regionValue(tester).statusBarIconBrightness, Brightness.dark);
      expect(
        _regionValue(tester).systemNavigationBarColor,
        MereytoiColors.light.navigationBackground,
      );
    });

    testWidgets('ThemeMode.dark', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(themeModeProvider.notifier).setMode(ThemeMode.dark);

      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: _harness()),
      );

      expect(_regionValue(tester).statusBarIconBrightness, Brightness.light);
      expect(
        _regionValue(tester).systemNavigationBarColor,
        MereytoiColors.dark.navigationBackground,
      );
    });

    testWidgets(
      'ThemeMode.system resolves against the platform brightness (light here)',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue =
            Brightness.light;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container.read(themeModeProvider.notifier).setMode(ThemeMode.system);

        await tester.pumpWidget(
          UncontrolledProviderScope(container: container, child: _harness()),
        );

        expect(_regionValue(tester).statusBarIconBrightness, Brightness.dark);
      },
    );

    testWidgets(
      'switching theme mid-session updates the overlay style and never resets cart state',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container.read(themeModeProvider.notifier).setMode(ThemeMode.dark);

        await tester.pumpWidget(
          UncontrolledProviderScope(container: container, child: _harness()),
        );
        expect(_regionValue(tester).statusBarIconBrightness, Brightness.light);

        await container.read(cartProvider.notifier).ready;
        container
            .read(cartProvider.notifier)
            .addItem(
              CartItem.fromListing(
                const Listing(
                  id: 99,
                  categoryId: 1,
                  nameRu: 'Тестовая услуга',
                  nameKz: 'Тестовая услуга',
                  descriptionRu: '',
                  descriptionKz: '',
                  city: '',
                  phone: '',
                  price: 10000,
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
        expect(container.read(cartProvider), hasLength(1));

        container.read(themeModeProvider.notifier).setMode(ThemeMode.light);
        await tester.pump();
        await tester.pump();

        expect(_regionValue(tester).statusBarIconBrightness, Brightness.dark);
        // The theme switch never touched cart state — same item, still
        // there, exactly brief requirement 10's own "сохранение состояния
        // корзины... при смене темы".
        expect(container.read(cartProvider), hasLength(1));
        expect(container.read(cartProvider).single.name, 'Тестовая услуга');
      },
    );
  });
}
