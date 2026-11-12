import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/models/category.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/screens/service_detail/service_detail_screen.dart';
import 'package:mereytoi_app/screens/services/services_screen.dart';
import 'package:mereytoi_app/state/categories_provider.dart';
import 'package:mereytoi_app/state/listings_provider.dart';
import 'package:mereytoi_app/state/locale_provider.dart';
import 'package:mereytoi_app/state/providers.dart';
import 'package:mereytoi_app/widgets/services/services_category_grid.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/city_fake_api.dart';

import '../helpers/fake_catalog.dart';

const _categories = [
  Category(
    id: 2,
    slug: 'hosts',
    nameRu: 'Ведущие',
    nameKz: 'Жүргізушілер',
    position: 1,
  ),
  Category(
    id: 3,
    slug: 'equipment',
    nameRu: 'Интерактивное оборудование и очень длинное продолжение',
    nameKz: 'Интерактивті жабдық және өте ұзын жалғасы бар атау',
    position: 2,
  ),
];

Listing _listing(int id, String name) => Listing(
  id: id,
  categoryId: 2,
  nameRu: name,
  nameKz: name,
  descriptionRu: '',
  descriptionKz: '',
  city: 'Алматы',
  phone: '',
  price: 500000,
  minGuests: 0,
  maxGuests: 0,
  rating: 5,
  emoji: '',
  colorFrom: '',
  colorTo: '',
  imageUrls: const [],
  isActive: true,
);

final _all = [for (var i = 1; i <= 24; i++) _listing(i, 'Услуга $i')];
final _hosts = [for (var i = 101; i <= 124; i++) _listing(i, 'Ведущий $i')];

Finder _card(int id) => find.byKey(ValueKey('service-grid-$id'));

double _scrollOffset(WidgetTester tester) => tester
    .state<ScrollableState>(find.byType(Scrollable).first)
    .position
    .pixels;

String _searchText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  AppLocale locale = AppLocale.ru,
  ThemeData? theme,
  String? slug,
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
        listingsProvider(null).overrideWith((ref) => Future.value(_all)),
        fakeCatalog({
          null: Future.value(_all),
          'hosts': Future.value(_hosts),
          'equipment': Future.value(_hosts),
        }),
        listingsProvider('hosts').overrideWith((ref) => Future.value(_hosts)),
        listingsProvider(
          'equipment',
        ).overrideWith((ref) => Future.value(_hosts)),
        for (final l in [..._all, ..._hosts])
          listingDetailProvider(l.id).overrideWith((ref) => Future.value(l)),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light,
        home: ServicesScreen(initialCategorySlug: slug),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester tester, int id) async {
  await tester.scrollUntilVisible(
    _card(id),
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _openCategory(WidgetTester tester, String name) async {
  await tester.ensureVisible(find.text(name));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the catalog is a tab root: no back button, no «Все» tile', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.byType(BackButton), findsNothing);
    expect(find.text('Все'), findsNothing);
    expect(find.byType(ServicesCategoryTile), findsNWidgets(2));
  });

  testWidgets(
    'a category opens its own screen from the top, with back and its name',
    (tester) async {
      await _pump(tester);
      await _scrollTo(tester, 7);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
      await tester.pumpAndSettle();
      await _openCategory(tester, 'Ведущие');

      expect(find.byType(BackButton), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Ведущие'),
        ),
        findsOneWidget,
      );
      expect(find.byType(ServicesCategoryTile), findsNothing);
      expect(_scrollOffset(tester), 0);
      expect(_card(101), findsOneWidget);
    },
  );

  testWidgets('a screen opened directly for a category has no picker', (
    tester,
  ) async {
    await _pump(tester, slug: 'hosts');
    expect(find.byType(ServicesCategoryTile), findsNothing);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Ведущие')),
      findsOneWidget,
    );
  });

  testWidgets('a service opens its own screen, with back and its name', (
    tester,
  ) async {
    await _pump(tester, slug: 'hosts');
    await tester.tap(_card(101));
    await tester.pumpAndSettle();

    expect(find.byType(ServiceDetailScreen), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SliverAppBar),
        matching: find.text('Ведущий 101'),
      ),
      findsOneWidget,
    );
    expect(_card(102), findsNothing);
    expect(_scrollOffset(tester), 0);
    // The service's own actions are still there.
    expect(find.byType(ElevatedButton), findsWidgets);
  });

  testWidgets('back from a service restores the list position', (tester) async {
    await _pump(tester, slug: 'hosts');
    await _scrollTo(tester, 115);
    final offset = _scrollOffset(tester);
    expect(offset, greaterThan(0));

    await tester.tap(_card(115));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.byType(ServiceDetailScreen), findsNothing);
    expect(_scrollOffset(tester), offset);
    expect(_card(115), findsOneWidget);
  });

  testWidgets('back from a category restores the catalog position', (
    tester,
  ) async {
    await _pump(tester);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -60));
    await tester.pumpAndSettle();
    final offset = _scrollOffset(tester);
    expect(offset, greaterThan(0));

    await tester.tap(find.text('Ведущие'));
    await tester.pumpAndSettle();
    expect(find.byType(ServicesCategoryTile), findsNothing);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(_scrollOffset(tester), offset);
  });

  testWidgets('searching hides the category grid; clearing brings it back', (
    tester,
  ) async {
    await _pump(tester);
    final field = find.byType(TextField);
    final fieldBottom = tester.getBottomLeft(field).dy;
    await tester.enterText(field, 'Услуга 1');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.byType(ServicesCategoryTile), findsNothing);
    expect(find.text('Категории'), findsNothing);
    expect(_card(1), findsOneWidget);
    expect(_card(2), findsNothing);
    // First result right under the field, past only the «Найдено» line.
    expect(tester.getTopLeft(_card(1)).dy, lessThan(fieldBottom + 100));

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(ServicesCategoryTile), findsNWidgets(2));
    expect(_card(2), findsOneWidget);
  });

  testWidgets('the catalog keeps its search across a service', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField), 'Услуга 1');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(_card(1));
    await tester.pumpAndSettle();
    expect(find.byType(ServiceDetailScreen), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(_searchText(tester), 'Услуга 1');
    expect(_card(2), findsNothing);
    expect(find.byType(ServicesCategoryTile), findsNothing);
  });

  for (final width in [320.0, 360.0]) {
    testWidgets(
      '${width.toInt()}dp: a long price keeps the cart button on screen',
      (tester) async {
        await _pump(tester, slug: 'hosts', size: Size(width, 700));
        await tester.tap(_card(101));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final cart = find.ancestor(
          of: find.byIcon(Icons.shopping_bag_outlined),
          matching: find.byWidgetPredicate((w) => w is ElevatedButton),
        );
        expect(tester.getRect(cart).right, lessThanOrEqualTo(width));
        expect(tester.getSize(cart).height, greaterThanOrEqualTo(48));
      },
    );
  }

  testWidgets('a category keeps its own search across a service', (
    tester,
  ) async {
    await _pump(tester, slug: 'hosts');
    await tester.enterText(find.byType(TextField), 'Ведущий 10');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(_card(101));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(_searchText(tester), 'Ведущий 10');
    expect(_card(110), findsNothing);
  });

  testWidgets('reset on an empty category clears only the search', (
    tester,
  ) async {
    await _pump(tester, slug: 'hosts');
    await tester.enterText(find.byType(TextField), 'нет такого');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Сбросить фильтры'));
    await tester.pumpAndSettle();

    expect(_card(101), findsOneWidget);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Ведущие')),
      findsOneWidget,
    );
  });

  for (final locale in AppLocale.values) {
    for (final themeName in ['light', 'dark']) {
      for (final width in [320.0, 390.0, 430.0]) {
        testWidgets(
          '${locale.name} $themeName ${width.toInt()}dp: long names do not overflow',
          (tester) async {
            await _pump(
              tester,
              size: Size(width, 700),
              locale: locale,
              theme: themeName == 'light' ? AppTheme.light : AppTheme.dark,
            );
            await tester.tap(find.byType(ServicesCategoryTile).at(1));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final back = tester.getSize(find.byType(BackButton));
            expect(back.height, greaterThanOrEqualTo(48));
            expect(back.width, greaterThanOrEqualTo(48));

            await tester.tap(_card(101));
            await tester.pumpAndSettle();
            expect(find.byType(BackButton), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
