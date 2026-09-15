import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/domain/restaurant/restaurant_price_calculator.dart';
import 'package:mereytoi_app/models/listing_menu_extra.dart';
import 'package:mereytoi_app/models/restaurant_selection.dart';
import 'package:mereytoi_app/state/locale_provider.dart';

void main() {
  group('RestaurantSelection.fromBreakdown', () {
    test(
      'maps every field the same way handleAddToCart builds its payload on the web',
      () {
        final extra = ListingMenuExtra(
          id: 9,
          menuId: 1,
          type: 'kids_table',
          titleRu: 'Детский стол',
          titleKz: 'Балалар үстелі',
          price: 12000,
          unit: 'per_guest',
          sortOrder: 0,
        );
        final breakdown = RestaurantPriceCalculator.calculate(
          pricePerGuest: 25000,
          guests: 50,
          selectedExtras: [extra],
        );

        final selection = RestaurantSelection.fromBreakdown(
          listingId: 16,
          hallId: 3,
          hallName: 'Sultan Hall',
          menuId: 1,
          menuName: 'Меню 25000',
          menuPricePerGuest: 25000,
          guests: 50,
          breakdown: breakdown,
          locale: AppLocale.ru,
        );

        expect(selection.listingId, 16);
        expect(selection.hallId, 3);
        expect(selection.hallName, 'Sultan Hall');
        expect(selection.menuId, 1);
        expect(selection.menuName, 'Меню 25000');
        expect(selection.menuPricePerGuest, 25000);
        expect(selection.guests, 50);
        expect(selection.estimatedTotal, breakdown.estimatedTotal);

        expect(selection.selectedExtras, hasLength(1));
        final line = selection.selectedExtras.single;
        expect(line.title, 'Детский стол');
        expect(line.price, 12000);
        expect(line.unit, 'per_guest');
        expect(line.amount, 12000 * 50);
      },
    );

    test(
      'hallId/hallName are both nullable — an "any hall" menu never invents a hall',
      () {
        final breakdown = RestaurantPriceCalculator.calculate(
          pricePerGuest: 15000,
          guests: 10,
          selectedExtras: const [],
        );
        final selection = RestaurantSelection.fromBreakdown(
          listingId: 5,
          menuId: 2,
          menuName: 'Меню без зала',
          menuPricePerGuest: 15000,
          guests: 10,
          breakdown: breakdown,
          locale: AppLocale.ru,
        );

        expect(selection.hallId, isNull);
        expect(selection.hallName, isNull);
        expect(selection.selectedExtras, isEmpty);
        expect(selection.estimatedTotal, 150000);
      },
    );
  });
}
