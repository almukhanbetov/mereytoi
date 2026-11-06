import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/models/category.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/screens/home/home_screen.dart';
import 'package:mereytoi_app/screens/services/services_screen.dart';
import 'package:mereytoi_app/state/categories_provider.dart';
import 'package:mereytoi_app/state/listings_provider.dart';
import 'package:mereytoi_app/widgets/service_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

Listing _listing(int id, String name, double rating) => Listing.fromJson({
  'id': id,
  'category_id': 2,
  'name_ru': name,
  'name_kz': name,
  'description_ru': '',
  'description_kz': '',
  'city': 'Алматы',
  'price': 1000,
  'rating': rating,
  'is_active': true,
});

void main() {
  // As the API returns them: newest first, whatever the rating.
  final fromApi = [
    _listing(30, 'Новая', 0),
    _listing(20, 'Средняя', 3),
    _listing(10, 'Старая с рейтингом', 5),
  ];

  testWidgets('the catalog keeps the API order, newest first', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          categoriesProvider.overrideWith(
            (ref) => Future.value(const <Category>[]),
          ),
          listingsProvider(null).overrideWith((ref) => Future.value(fromApi)),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const ServicesScreen()),
      ),
    );
    await tester.pumpAndSettle();
    final cards = tester.widgetList<ServiceGridCard>(
      find.byType(ServiceGridCard),
    );
    expect(cards.map((c) => c.listing.id), [30, 20, 10]);
  });

  test('«Популярное» stays by rating, ties to the newest', () {
    final popular = homePopularListings([
      _listing(40, 'Новая с тем же рейтингом', 5),
      ...fromApi,
    ]);
    expect(popular.map((l) => l.id).toList(), [40, 10, 20, 30]);
    expect(fromApi.first.id, 30); // the catalog's own list isn't reordered
  });
}
