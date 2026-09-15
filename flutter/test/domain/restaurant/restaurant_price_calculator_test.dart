import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/domain/restaurant/restaurant_price_calculator.dart';
import 'package:mereytoi_app/models/listing_menu_extra.dart';

ListingMenuExtra _extra({
  required int id,
  required String unit,
  required int price,
  int sortOrder = 0,
}) {
  return ListingMenuExtra(
    id: id,
    menuId: 1,
    type: 'other',
    titleRu: 'Extra $id',
    titleKz: 'Extra $id',
    price: price,
    unit: unit,
    sortOrder: sortOrder,
  );
}

void main() {
  group(
    'RestaurantPriceCalculator.calculate — exact port of RestaurantMenuCalculator.jsx',
    () {
      test('base price only — no extras selected', () {
        final breakdown = RestaurantPriceCalculator.calculate(
          pricePerGuest: 25000,
          guests: 50,
          selectedExtras: const [],
        );

        expect(breakdown.basePrice, 1250000);
        expect(breakdown.extrasTotal, 0);
        expect(breakdown.estimatedTotal, 1250000);
        expect(breakdown.flatLines, isEmpty);
        expect(breakdown.percentLines, isEmpty);
      });

      test('a fixed (flat) extra is added once, regardless of guest count', () {
        final extra = _extra(id: 1, unit: '', price: 15000);
        final breakdown = RestaurantPriceCalculator.calculate(
          pricePerGuest: 25000,
          guests: 50,
          selectedExtras: [extra],
        );

        expect(breakdown.flatLines, hasLength(1));
        expect(breakdown.flatLines.single.amount, 15000);
        expect(breakdown.extrasTotal, 15000);
        expect(breakdown.estimatedTotal, 1250000 + 15000);
      });

      test('a per_guest extra scales with the guest count', () {
        final extra = _extra(id: 2, unit: 'per_guest', price: 2000);
        final breakdown = RestaurantPriceCalculator.calculate(
          pricePerGuest: 25000,
          guests: 50,
          selectedExtras: [extra],
        );

        expect(breakdown.flatLines.single.amount, 2000 * 50);
        expect(breakdown.estimatedTotal, 1250000 + 100000);
      });

      test(
        'a percent extra is computed on (basePrice + flat extras), after flat extras are folded in — order matters',
        () {
          final flat = _extra(id: 3, unit: '', price: 15000, sortOrder: 0);
          final percent = _extra(
            id: 4,
            unit: 'percent',
            price: 10,
            sortOrder: 1,
          );
          final breakdown = RestaurantPriceCalculator.calculate(
            pricePerGuest: 25000,
            guests: 50,
            selectedExtras: [flat, percent],
          );

          // beforePercent = 1 250 000 + 15 000 = 1 265 000
          // percent amount = round(1 265 000 * 10 / 100) = 126 500
          expect(breakdown.percentLines.single.amount, 126500);
          expect(breakdown.estimatedTotal, 1250000 + 15000 + 126500);
        },
      );

      test(
        'multiple extras combine: flat + per_guest + percent, all selected together',
        () {
          final flat = _extra(id: 5, unit: '', price: 10000, sortOrder: 0);
          final perGuest = _extra(
            id: 6,
            unit: 'per_guest',
            price: 1500,
            sortOrder: 1,
          );
          final percent = _extra(
            id: 7,
            unit: 'percent',
            price: 5,
            sortOrder: 2,
          );
          final breakdown = RestaurantPriceCalculator.calculate(
            pricePerGuest: 20000,
            guests: 80,
            selectedExtras: [flat, perGuest, percent],
          );

          // basePrice = 1 600 000
          // flatSum = 10 000 + (1 500*80=120 000) = 130 000
          // beforePercent = 1 730 000
          // percent = round(1 730 000 * 5 / 100) = 86 500
          expect(breakdown.basePrice, 1600000);
          expect(breakdown.flatLines, hasLength(2));
          expect(breakdown.extrasTotal, 130000 + 86500);
          expect(breakdown.estimatedTotal, 1600000 + 130000 + 86500);
        },
      );

      test(
        'unit matching is case/whitespace-insensitive, mirroring isPercentUnit/isPerGuestUnit',
        () {
          expect(RestaurantPriceCalculator.isPercentUnit(' Percent '), isTrue);
          expect(RestaurantPriceCalculator.isPerGuestUnit('PER_GUEST'), isTrue);
          expect(RestaurantPriceCalculator.isPercentUnit('flat'), isFalse);
        },
      );
    },
  );
}
