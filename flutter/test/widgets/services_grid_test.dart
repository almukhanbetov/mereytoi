import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/core/utils/format.dart';
import 'package:mereytoi_app/models/category.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/screens/services/services_screen.dart';
import 'package:mereytoi_app/state/categories_provider.dart';
import 'package:mereytoi_app/state/listings_provider.dart';
import 'package:mereytoi_app/state/locale_provider.dart';
import 'package:mereytoi_app/state/providers.dart';
import 'package:mereytoi_app/widgets/app_skeleton.dart';
import 'package:mereytoi_app/widgets/service_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/city_fake_api.dart';

const _categories = [
  Category(
    id: 2,
    slug: 'hosts',
    nameRu: 'Ведущие',
    nameKz: 'Жүргізушілер',
    position: 1,
  ),
];

Listing _listing(
  int id,
  String name, {
  int price = 500000,
  double rating = 5,
  String city = 'Алматы',
}) => Listing(
  id: id,
  categoryId: 2,
  nameRu: name,
  nameKz: name,
  descriptionRu: '',
  descriptionKz: '',
  city: city,
  phone: '',
  price: price,
  minGuests: 0,
  maxGuests: 0,
  rating: rating,
  emoji: '',
  colorFrom: '',
  colorTo: '',
  imageUrls: const [],
  isActive: true,
);

final _listings = [
  _listing(1, 'Ардак Тамада'),
  _listing(
    2,
    'Очень длинное название услуги, которое точно не поместится в две '
    'строки карточки каталога',
    city: 'Усть-Каменогорск (очень длинное уточнение района)',
  ),
  _listing(3, 'Бесплатная консультация', price: 0, rating: 0),
  _listing(4, 'Шоу мыльных пузырей', price: 123456789),
  _listing(5, 'Ведущий 5'),
];

void main() {
  Future<void> pumpServices(
    WidgetTester tester, {
    Size size = const Size(390, 900),
    ThemeData Function()? theme,
    AppLocale locale = AppLocale.ru,
    double textScale = 1,
    Future<List<Listing>>? listings,
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
          listingsProvider(
            null,
          ).overrideWith((ref) => listings ?? Future.value(_listings)),
        ],
        child: MaterialApp(
          theme: (theme ?? () => AppTheme.light)(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const ServicesScreen(),
        ),
      ),
    );
    if (listings == null) {
      await tester.pumpAndSettle();
    } else {
      // Loading skeletons shimmer forever — pump a few frames instead.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
  }

  Finder card(int id) => find.byKey(ValueKey('service-grid-$id'));

  Future<void> showCard(WidgetTester tester, int id) async {
    await tester.scrollUntilVisible(
      card(id),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('two columns, equal heights whatever the name length', (
    tester,
  ) async {
    await pumpServices(tester, size: const Size(390, 2400));
    final a = tester.getRect(card(1));
    final b = tester.getRect(card(2));
    final c = tester.getRect(card(3));
    // 1 and 2 share a row, 3 starts the next one under 1.
    expect(a.top, b.top);
    expect(a.left, lessThan(b.left));
    expect(c.left, a.left);
    expect(c.top, greaterThan(a.bottom));
    // Short and very long names: the same card height.
    expect(a.height, b.height);
    expect(a.height, c.height);
    // 16 outer padding, 12 between columns.
    expect(a.left, 16);
    expect(b.left - a.right, 12);
    expect(390 - b.right, 16);
    expect(a.width, b.width);
  });

  testWidgets('first load: the skeleton is the same 2-column grid', (
    tester,
  ) async {
    final pending = Completer<List<Listing>>();
    await pumpServices(
      tester,
      size: const Size(390, 2400),
      listings: pending.future,
    );
    final tiles = find.byWidgetPredicate(
      (w) => w is AppSkeleton && w.borderRadius == 16,
    );
    expect(tiles, findsNWidgets(6));
    final a = tester.getRect(tiles.at(0));
    final b = tester.getRect(tiles.at(1));
    expect(a.top, b.top);
    expect(a.width, b.width);
    expect(a.left, 16);
    pending.complete(_listings);
    await tester.pumpAndSettle();
    expect(find.byType(ServiceGridCard), findsWidgets);
  });

  testWidgets('photo square on top, rating badge, name, city, price', (
    tester,
  ) async {
    await pumpServices(tester, size: const Size(390, 2400));
    final first = tester.getRect(card(1));
    final photo = tester.getRect(
      find.descendant(of: card(1), matching: find.byType(AspectRatio)),
    );
    expect(photo.top, first.top);
    expect(photo.width, first.width);
    expect(photo.height, photo.width);
    expect(
      find.descendant(of: card(1), matching: find.text('5.0')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card(1), matching: find.text('Ардак Тамада')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card(1), matching: find.text('Алматы')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card(1), matching: find.text(formatPrice(500000))),
      findsOneWidget,
    );
  });

  testWidgets('no rating → no badge; a 0 price reads «0 ₸»', (tester) async {
    await pumpServices(tester, size: const Size(390, 2400));
    expect(
      find.descendant(of: card(3), matching: find.byIcon(Icons.star_rounded)),
      findsNothing,
    );
    expect(
      find.descendant(of: card(3), matching: find.text('0 ₸')),
      findsOneWidget,
    );
  });

  testWidgets('the last card scrolls clear of the bottom', (tester) async {
    await pumpServices(tester, size: const Size(390, 700));
    await showCard(tester, 5);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
    await tester.pumpAndSettle();
    // At least the chat button's clearance stays below the last card.
    expect(tester.getRect(card(5)).bottom, lessThan(700 - 80));
  });

  group('no overflow', () {
    final themes = <(String, ThemeData Function())>[
      ('light', () => AppTheme.light),
      ('dark', () => AppTheme.dark),
    ];
    for (final theme in themes) {
      for (final width in [320.0, 390.0, 430.0]) {
        for (final locale in AppLocale.values) {
          for (final scale in [1.0, 1.3, 2.0]) {
            testWidgets(
              '${theme.$1} · ${width.toInt()} · ${locale.name} · ×$scale',
              (tester) async {
                await pumpServices(
                  tester,
                  size: Size(width, 3000),
                  theme: theme.$2,
                  locale: locale,
                  textScale: scale,
                );
                expect(find.byType(ServiceGridCard), findsWidgets);
                expect(tester.takeException(), isNull);
                // Still two columns, even at 320dp.
                expect(
                  tester.getRect(card(1)).top,
                  tester.getRect(card(2)).top,
                );
              },
            );
          }
        }
      }
    }
  });
}
