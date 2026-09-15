import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/domain/checkout/checkout_validation.dart';
import 'package:mereytoi_app/models/cart_item.dart';
import 'package:mereytoi_app/models/listing.dart';

Listing _ordinaryListing() => Listing(
  id: 5,
  categoryId: 1,
  nameRu: 'Ведущий',
  nameKz: 'Ведущий',
  descriptionRu: '',
  descriptionKz: '',
  city: 'Алматы',
  phone: '',
  price: 250000,
  minGuests: 0,
  maxGuests: 0,
  rating: 0,
  emoji: '',
  colorFrom: '',
  colorTo: '',
  imageUrls: const [],
  isActive: true,
);

CartItem _restaurantItem({int guests = 100, int? estimatedTotal = 2500000}) =>
    CartItem(
      listingId: 42,
      name: 'Sultan Palace · Меню',
      category: 'Рестораны',
      image: null,
      unitPrice: 25000,
      guests: guests,
      totalPrice: estimatedTotal ?? 0,
      hallId: 1,
      hallName: 'Sultan Hall',
      menuId: 2,
      menuName: 'Меню',
      menuPricePerGuest: 25000,
      estimatedTotal: estimatedTotal,
    );

void main() {
  group('14. validateCartForCheckout', () {
    test('an empty cart is refused with emptyCart', () {
      final result = validateCartForCheckout(const []);
      expect(result.isValid, isFalse);
      expect(result.reason, CheckoutBlockReason.emptyCart);
    });

    test('an ordinary service is always valid regardless of guests', () {
      final item = CartItem.fromListing(
        _ordinaryListing(),
        name: 'Ведущий',
        categoryLabel: 'Ведущие',
      );
      final result = validateCartForCheckout([item]);
      expect(result.isValid, isTrue);
      expect(result.reason, isNull);
    });

    test('a restaurant variant with a real snapshot is valid', () {
      final result = validateCartForCheckout([_restaurantItem()]);
      expect(result.isValid, isTrue);
    });

    test('a restaurant variant missing its estimated_total is refused', () {
      final result = validateCartForCheckout([
        _restaurantItem(estimatedTotal: null),
      ]);
      expect(result.isValid, isFalse);
      expect(result.reason, CheckoutBlockReason.missingEstimatedTotal);
    });

    test('a restaurant variant with zero/negative guests is refused', () {
      final result = validateCartForCheckout([_restaurantItem(guests: 0)]);
      expect(result.isValid, isFalse);
      expect(result.reason, CheckoutBlockReason.invalidGuestCount);
    });

    test('one bad item among several valid ones still blocks checkout', () {
      final ok = _restaurantItem();
      final bad = _restaurantItem(estimatedTotal: null);
      final result = validateCartForCheckout([ok, bad]);
      expect(result.isValid, isFalse);
    });
  });

  group('15/16. isGuestCountWithinBounds — min/max guests', () {
    test('below the minimum is out of bounds', () {
      expect(isGuestCountWithinBounds(30, min: 50, max: 300), isFalse);
    });

    test('exactly the minimum is within bounds', () {
      expect(isGuestCountWithinBounds(50, min: 50, max: 300), isTrue);
    });

    test('above the maximum is out of bounds', () {
      expect(isGuestCountWithinBounds(301, min: 50, max: 300), isFalse);
    });

    test('exactly the maximum is within bounds', () {
      expect(isGuestCountWithinBounds(300, min: 50, max: 300), isTrue);
    });

    test('no upper bound (max == null) never rejects on the high end', () {
      expect(isGuestCountWithinBounds(100000, min: 1, max: null), isTrue);
    });
  });

  group('23. restaurant snapshot immutability — the mandatory scenario', () {
    test(
      'a cart item built before a later live price/selection change keeps its own frozen numbers',
      () {
        // Select Hall A / Menu B, 100 guests, priced at 25 000/guest, an
        // extra applied — add to cart.
        final item = _restaurantItem(guests: 100, estimatedTotal: 2620000);

        // The live listing/menu now changes underneath it (a different
        // price, different guest count someone else is looking at) — but
        // nothing re-touches this already-added CartItem.
        // `validateCartForCheckout`/`toBookingItemJson` must both still see
        // exactly the old numbers.
        expect(item.guests, 100);
        expect(item.menuPricePerGuest, 25000);
        expect(item.estimatedTotal, 2620000);
        expect(item.totalPrice, 2620000);

        final payload = item.toBookingItemJson();
        expect(payload['guests'], 100);
        expect(payload['menu_price_per_guest'], 25000);
        expect(payload['estimated_total'], 2620000);
        expect(payload['total_price'], 2620000);

        final validation = validateCartForCheckout([item]);
        expect(validation.isValid, isTrue);
      },
    );
  });
}
