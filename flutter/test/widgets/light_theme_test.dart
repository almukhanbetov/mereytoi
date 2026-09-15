import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/models/cart_item.dart';
import 'package:mereytoi_app/models/category.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/models/site_statistics.dart';
import 'package:mereytoi_app/screens/auth/login_screen.dart';
import 'package:mereytoi_app/screens/cart/cart_screen.dart';
import 'package:mereytoi_app/screens/checkout/checkout_screen.dart';
import 'package:mereytoi_app/screens/home/home_screen.dart';
import 'package:mereytoi_app/screens/root_shell.dart';
import 'package:mereytoi_app/state/cart_provider.dart';
import 'package:mereytoi_app/state/categories_provider.dart';
import 'package:mereytoi_app/state/listings_provider.dart';
import 'package:mereytoi_app/state/statistics_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 13. "несколько widget tests ключевых экранов в light theme" — the same
/// screens already covered under dark in earlier stages' overflow tests,
/// now pumped with `theme: AppTheme.light` / `themeMode: ThemeMode.light`
/// instead. These don't (and can't, without a real device/renderer)
/// measure actual pixel contrast — they do verify every one of these
/// screens builds cleanly under the light `ThemeData`/`MereytoiColors`
/// with no `RenderFlex`/theme-lookup exception, which is exactly the class
/// of bug (`Theme.of(context).extension<MereytoiColors>()` returning null,
/// a widget assuming dark-only colors and crashing, an overflow that only
/// appears once card backgrounds/text swap) light mode could newly expose.
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

Widget _wrapLight(Widget home, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.light,
      themeMode: ThemeMode.light,
      home: home,
    ),
  );
}

Listing _listing({int id = 1, String category = 'hosts'}) => Listing(
  id: id,
  categoryId: 1,
  category: Category(
    id: 1,
    slug: category,
    nameRu: 'Ведущие',
    nameKz: 'Жүргізушілер',
    position: 0,
  ),
  nameRu: 'AURORA QUINTET',
  nameKz: 'AURORA QUINTET',
  descriptionRu: 'Живая музыка на торжество',
  descriptionKz: 'Той үшін тірі музыка',
  city: 'Алматы',
  phone: '+7 700 123 45 67',
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

  testWidgets('HomeScreen renders under light theme with no exceptions', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrapLight(
        const HomeScreen(),
        overrides: [
          categoriesProvider.overrideWith(
            (ref) => Future.value(const <Category>[]),
          ),
          listingsProvider(
            null,
          ).overrideWith((ref) => Future.value([_listing()])),
          listingsProvider(
            'venues',
          ).overrideWith((ref) => Future.value(const [])),
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
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AURORA QUINTET'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'RootShell (bottom nav + all 4 tabs mounted) renders under light theme',
    (tester) async {
      await tester.pumpWidget(
        _wrapLight(
          const RootShell(),
          overrides: [
            categoriesProvider.overrideWith(
              (ref) => Future.value(const <Category>[]),
            ),
            listingsProvider(
              null,
            ).overrideWith((ref) => Future.value(const [])),
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
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Empty CartScreen renders under light theme', (tester) async {
    await tester.pumpWidget(_wrapLight(const CartScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Корзина пока пуста'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'CheckoutScreen with a real cart item renders under light theme (cards/text/dividers/inputs all theme-aware)',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(cartProvider.notifier).ready;
      container
          .read(cartProvider.notifier)
          .addItem(
            CartItem.fromListing(
              _listing(),
              name: 'Ведущий',
              categoryLabel: 'Ведущие',
            ),
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const CheckoutScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ведущий'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'LoginScreen (form/inputs/password field) renders under light theme',
    (tester) async {
      await tester.pumpWidget(_wrapLight(const LoginScreen()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );
}
