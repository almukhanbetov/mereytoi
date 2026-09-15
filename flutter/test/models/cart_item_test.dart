import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/domain/restaurant/restaurant_price_calculator.dart';
import 'package:mereytoi_app/models/cart_item.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/models/listing_menu_extra.dart';
import 'package:mereytoi_app/models/restaurant_selection.dart';
import 'package:mereytoi_app/state/locale_provider.dart';

void main() {
  group('CartItem.fromRestaurantSelection', () {
    test('maps every restaurant field and builds name as "listing · menu"', () {
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
        guests: 100,
        selectedExtras: [extra],
      );
      final selection = RestaurantSelection.fromBreakdown(
        listingId: 42,
        hallId: 1,
        hallName: 'Sultan Hall',
        menuId: 2,
        menuName: 'Банкетное меню №1',
        menuPricePerGuest: 25000,
        guests: 100,
        breakdown: breakdown,
        locale: AppLocale.ru,
      );

      final item = CartItem.fromRestaurantSelection(
        selection,
        listingName: 'Sultan Palace',
        categoryLabel: 'Рестораны',
        image: '/uploads/hall.jpg',
      );

      expect(item.listingId, 42);
      expect(item.name, 'Sultan Palace · Банкетное меню №1');
      expect(item.category, 'Рестораны');
      expect(item.image, '/uploads/hall.jpg');
      expect(item.hallId, 1);
      expect(item.hallName, 'Sultan Hall');
      expect(item.menuId, 2);
      expect(item.menuName, 'Банкетное меню №1');
      expect(item.menuPricePerGuest, 25000);
      expect(item.guests, 100);
      expect(item.unitPrice, 25000);
      expect(item.totalPrice, breakdown.estimatedTotal);
      expect(item.estimatedTotal, breakdown.estimatedTotal);
      expect(item.selectedExtras, hasLength(1));
      expect(item.key, (listingId: 42, hallId: 1, menuId: 2));
    });
  });

  group('serialize/deserialize — ordinary service', () {
    test('round-trips through JSON with no restaurant fields set', () {
      final item = CartItem.fromListing(
        Listing(
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
          imageUrls: const ['/uploads/a.jpg'],
          isActive: true,
        ),
        name: 'Ведущий',
        categoryLabel: 'Ведущие',
      );

      final restored = CartItem.fromJson(item.toJson());

      expect(restored.listingId, item.listingId);
      expect(restored.name, item.name);
      expect(restored.totalPrice, item.totalPrice);
      expect(restored.hallId, isNull);
      expect(restored.menuId, isNull);
      expect(restored.selectedExtras, isEmpty);
      expect(restored.estimatedTotal, isNull);
      expect(restored.key, (listingId: 5, hallId: null, menuId: null));
    });
  });

  group('serialize/deserialize — restaurant variant', () {
    test('round-trips the full snapshot, including selectedExtras', () {
      final extra = ListingMenuExtra(
        id: 9,
        menuId: 1,
        type: 'service_fee',
        titleRu: 'Сервисный сбор',
        titleKz: 'Қызмет ақысы',
        price: 10,
        unit: 'percent',
        sortOrder: 0,
      );
      final breakdown = RestaurantPriceCalculator.calculate(
        pricePerGuest: 25000,
        guests: 120,
        selectedExtras: [extra],
      );
      final selection = RestaurantSelection.fromBreakdown(
        listingId: 42,
        hallId: 1,
        hallName: 'Sultan Hall',
        menuId: 2,
        menuName: 'Банкетное меню №1',
        menuPricePerGuest: 25000,
        guests: 120,
        breakdown: breakdown,
        locale: AppLocale.ru,
      );
      final item = CartItem.fromRestaurantSelection(
        selection,
        listingName: 'Sultan Palace',
        categoryLabel: 'Рестораны',
      );

      final restored = CartItem.fromJson(item.toJson());

      expect(restored.hallId, 1);
      expect(restored.hallName, 'Sultan Hall');
      expect(restored.menuId, 2);
      expect(restored.menuName, 'Банкетное меню №1');
      expect(restored.menuPricePerGuest, 25000);
      expect(restored.guests, 120);
      expect(restored.estimatedTotal, item.estimatedTotal);
      expect(restored.selectedExtras, hasLength(1));
      expect(restored.selectedExtras.single.title, 'Сервисный сбор');
      expect(restored.selectedExtras.single.unit, 'percent');
      expect(
        restored.selectedExtras.single.amount,
        item.selectedExtras.single.amount,
      );
    });

    test(
      'estimatedTotal is a frozen snapshot — it does not change if the same JSON is decoded again later',
      () {
        final item = CartItem(
          listingId: 42,
          name: 'Sultan Palace · Меню',
          category: 'Рестораны',
          image: null,
          unitPrice: 25000,
          guests: 100,
          totalPrice: 2500000,
          hallId: 1,
          menuId: 2,
          menuPricePerGuest: 25000,
          estimatedTotal: 2500000,
        );
        final json = item.toJson();

        // Decoding the same persisted snapshot twice must always produce the
        // same numbers — nothing here re-derives the total from a "current"
        // price per guest or guest count.
        final first = CartItem.fromJson(json);
        final second = CartItem.fromJson(json);
        expect(first.estimatedTotal, 2500000);
        expect(second.estimatedTotal, 2500000);
        expect(first.menuPricePerGuest, 25000);
      },
    );
  });

  group('migration safety — old (pre-Stage-3) cart JSON', () {
    test(
      'a JSON object with none of the restaurant keys parses without throwing, defaulting to null/[]',
      () {
        final oldJson = {
          'listing_id': 7,
          'name': 'Тамада',
          'category': 'Ведущие',
          'image': '/uploads/x.jpg',
          'unit_price': 180000,
          'guests': 0,
          'total_price': 180000,
          // hall_id/hall_name/menu_id/menu_name/menu_price_per_guest/
          // selected_extras/estimated_total all deliberately absent —
          // exactly what a cart saved before Stage 3 would contain.
        };

        final item = CartItem.fromJson(oldJson);

        expect(item.listingId, 7);
        expect(item.totalPrice, 180000);
        expect(item.hallId, isNull);
        expect(item.hallName, isNull);
        expect(item.menuId, isNull);
        expect(item.menuName, isNull);
        expect(item.menuPricePerGuest, isNull);
        expect(item.selectedExtras, isEmpty);
        expect(item.estimatedTotal, isNull);
      },
    );
  });

  group('toBookingItemJson', () {
    test(
      'an ordinary service keeps the old, backward-compatible payload shape',
      () {
        final item = CartItem.fromListing(
          Listing(
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
          ),
          name: 'Ведущий',
          categoryLabel: 'Ведущие',
        );

        final json = item.toBookingItemJson();

        expect(json['listing_id'], 5);
        expect(json['name'], 'Ведущий');
        expect(json['guests'], 0);
        expect(json['unit_price'], 250000);
        expect(json['total_price'], 250000);
        expect(json['hall_id'], isNull);
        expect(json['menu_id'], isNull);
        expect(json['selected_extras'], isEmpty);
        expect(json['estimated_total'], 0);
      },
    );

    test(
      'a restaurant variant payload matches bookingItemInput exactly: listing_id/hall_id/hall_name/menu_id/menu_name/menu_price_per_guest/guests/selected_extras/estimated_total',
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
          guests: 100,
          selectedExtras: [extra],
        );
        final selection = RestaurantSelection.fromBreakdown(
          listingId: 42,
          hallId: 1,
          hallName: 'Sultan Hall',
          menuId: 2,
          menuName: 'Банкетное меню №1',
          menuPricePerGuest: 25000,
          guests: 100,
          breakdown: breakdown,
          locale: AppLocale.ru,
        );
        final item = CartItem.fromRestaurantSelection(
          selection,
          listingName: 'Sultan Palace',
          categoryLabel: 'Рестораны',
        );

        final json = item.toBookingItemJson();

        expect(json['listing_id'], 42);
        expect(json['hall_id'], 1);
        expect(json['hall_name'], 'Sultan Hall');
        expect(json['menu_id'], 2);
        expect(json['menu_name'], 'Банкетное меню №1');
        expect(json['menu_price_per_guest'], 25000);
        expect(json['guests'], 100);
        expect(json['estimated_total'], breakdown.estimatedTotal);
        expect(json['total_price'], breakdown.estimatedTotal);

        final extrasJson = json['selected_extras'] as List;
        expect(extrasJson, hasLength(1));
        final extraJson = extrasJson.single as Map;
        // bookingItemExtraInput on the backend only declares title/price/
        // unit — no "amount" field, so this payload must not send one.
        expect(extraJson.keys, containsAll(['title', 'price', 'unit']));
        expect(extraJson.containsKey('amount'), isFalse);
        expect(extraJson['title'], 'Детский стол');
        expect(extraJson['unit'], 'per_guest');
      },
    );
  });
}
