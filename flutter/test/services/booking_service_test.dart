import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/network/api_client.dart';
import 'package:mereytoi_app/models/cart_item.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/domain/restaurant/restaurant_price_calculator.dart';
import 'package:mereytoi_app/models/listing_menu_extra.dart';
import 'package:mereytoi_app/models/restaurant_selection.dart';
import 'package:mereytoi_app/services/booking_service.dart';
import 'package:mereytoi_app/state/locale_provider.dart';

/// Same fake-adapter seam every other service test in this suite uses
/// (`ApiClient.test` + a routing `HttpClientAdapter`), echoing back
/// whatever `items` was actually sent as the `booking.items` the server
/// would return — lets these tests assert on the *request* payload shape
/// (brief section 2's six required combinations) without needing a second,
/// separately-written response fixture per case.
class _EchoAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  Map<String, dynamic>? extraResponseFields;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final body = options.data as Map;
    final items = (body['items'] as List).cast<Map>();
    var total = 0;
    for (final item in items) {
      total += item['total_price'] as int;
    }
    final data = {
      'booking': {
        'id': 1,
        'public_ref': 'abc123',
        'name': body['name'],
        'phone': body['phone'],
        'message': body['message'],
        'items': items,
        'total': total,
        'status': 'new',
        'created_at': '2026-01-01T00:00:00Z',
        ...?extraResponseFields,
      },
    };
    return ResponseBody.fromBytes(
      Uint8List.fromList(utf8.encode(jsonEncode(data))),
      201,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

(BookingService, _EchoAdapter) _service({
  Future<String?> Function()? tokenProvider,
}) {
  final adapter = _EchoAdapter();
  final client = ApiClient.test(
    tokenProvider: tokenProvider ?? () async => null,
  );
  client.debugDio.httpClientAdapter = adapter;
  return (BookingService(client), adapter);
}

Listing _ordinaryListing({int price = 250000}) => Listing(
  id: 5,
  categoryId: 1,
  nameRu: 'Ведущий',
  nameKz: 'Ведущий',
  descriptionRu: '',
  descriptionKz: '',
  city: 'Алматы',
  phone: '',
  price: price,
  minGuests: 0,
  maxGuests: 0,
  rating: 0,
  emoji: '',
  colorFrom: '',
  colorTo: '',
  imageUrls: const [],
  isActive: true,
);

CartItem _restaurantItem({int? hallId, String? hallName, required int menuId}) {
  final extra = ListingMenuExtra(
    id: 9,
    menuId: menuId,
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
    hallId: hallId,
    hallName: hallName,
    menuId: menuId,
    menuName: 'Банкетное меню №1',
    menuPricePerGuest: 25000,
    guests: 100,
    breakdown: breakdown,
    locale: AppLocale.ru,
  );
  return CartItem.fromRestaurantSelection(
    selection,
    listingName: 'Sultan Palace',
    categoryLabel: 'Рестораны',
  );
}

void main() {
  group('submitBooking payload shape — the 6 required combinations', () {
    test('1. ordinary service (no hall/no menu)', () async {
      final (service, adapter) = _service();
      final item = CartItem.fromListing(
        _ordinaryListing(),
        name: 'Ведущий',
        categoryLabel: 'Ведущие',
      );
      await service.submitBooking(
        name: 'Айгерим',
        phone: '+77001234567',
        items: [item],
      );
      final sentItem =
          ((adapter.requests.single.data as Map)['items'] as List).single
              as Map;
      expect(sentItem['hall_id'], isNull);
      expect(sentItem['menu_id'], isNull);
      expect(sentItem['hall_name'], '');
      expect(sentItem['menu_name'], '');
      expect(sentItem['estimated_total'], 0);
    });

    test(
      '2. restaurant — no hall, no menu selected beyond the base menu',
      () async {
        final (service, adapter) = _service();
        final item = _restaurantItem(hallId: null, hallName: null, menuId: 2);
        await service.submitBooking(name: 'A', phone: '+7700', items: [item]);
        final sentItem =
            ((adapter.requests.single.data as Map)['items'] as List).single
                as Map;
        expect(sentItem['hall_id'], isNull);
        expect(sentItem['menu_id'], 2);
      },
    );

    test('3. restaurant + hall', () async {
      final (service, adapter) = _service();
      final item = _restaurantItem(
        hallId: 1,
        hallName: 'Sultan Hall',
        menuId: 2,
      );
      await service.submitBooking(name: 'A', phone: '+7700', items: [item]);
      final sentItem =
          ((adapter.requests.single.data as Map)['items'] as List).single
              as Map;
      expect(sentItem['hall_id'], 1);
      expect(sentItem['hall_name'], 'Sultan Hall');
      expect(sentItem['menu_id'], 2);
    });

    test(
      '4. restaurant + menu (already covered by every case above; asserted explicitly)',
      () async {
        final (service, adapter) = _service();
        final item = _restaurantItem(hallId: null, hallName: null, menuId: 7);
        await service.submitBooking(name: 'A', phone: '+7700', items: [item]);
        final sentItem =
            ((adapter.requests.single.data as Map)['items'] as List).single
                as Map;
        expect(sentItem['menu_id'], 7);
        expect(sentItem['menu_name'], 'Банкетное меню №1');
        expect(sentItem['menu_price_per_guest'], 25000);
      },
    );

    test('5. restaurant + hall + menu', () async {
      final (service, adapter) = _service();
      final item = _restaurantItem(hallId: 3, hallName: 'VIP', menuId: 9);
      await service.submitBooking(name: 'A', phone: '+7700', items: [item]);
      final sentItem =
          ((adapter.requests.single.data as Map)['items'] as List).single
              as Map;
      expect(sentItem['hall_id'], 3);
      expect(sentItem['hall_name'], 'VIP');
      expect(sentItem['menu_id'], 9);
    });

    test(
      '6. with extras — selected_extras carries only title/price/unit',
      () async {
        final (service, adapter) = _service();
        final item = _restaurantItem(
          hallId: 1,
          hallName: 'Sultan Hall',
          menuId: 2,
        );
        await service.submitBooking(name: 'A', phone: '+7700', items: [item]);
        final sentItem =
            ((adapter.requests.single.data as Map)['items'] as List).single
                as Map;
        final extras = sentItem['selected_extras'] as List;
        expect(extras, hasLength(1));
        final extra = extras.single as Map;
        expect(extra.keys, containsAll(['title', 'price', 'unit']));
        expect(extra.containsKey('amount'), isFalse);
      },
    );

    test(
      '7. estimated_total is sent as the frozen cart snapshot, not recomputed',
      () async {
        final (service, adapter) = _service();
        final item = _restaurantItem(
          hallId: 1,
          hallName: 'Sultan Hall',
          menuId: 2,
        );
        await service.submitBooking(name: 'A', phone: '+7700', items: [item]);
        final sentItem =
            ((adapter.requests.single.data as Map)['items'] as List).single
                as Map;
        expect(sentItem['estimated_total'], item.estimatedTotal);
        expect(sentItem['total_price'], item.totalPrice);
      },
    );
  });

  test(
    '22. auth/anonymous — a checkout with no session token sends no Authorization header',
    () async {
      final (service, adapter) = _service(tokenProvider: () async => null);
      final item = CartItem.fromListing(
        _ordinaryListing(),
        name: 'Ведущий',
        categoryLabel: 'Ведущие',
      );
      await service.submitBooking(name: 'A', phone: '+7700', items: [item]);
      expect(
        adapter.requests.single.headers.containsKey('Authorization'),
        isFalse,
      );
    },
  );

  test(
    'a logged-in checkout still sends the Bearer token — booking creation never forces logout',
    () async {
      final (service, adapter) = _service(
        tokenProvider: () async => 'jwt-token',
      );
      final item = CartItem.fromListing(
        _ordinaryListing(),
        name: 'Ведущий',
        categoryLabel: 'Ведущие',
      );
      await service.submitBooking(name: 'A', phone: '+7700', items: [item]);
      expect(
        adapter.requests.single.headers['Authorization'],
        'Bearer jwt-token',
      );
    },
  );

  test(
    'BookingCreateResult parses the booking object from the response, including event_id',
    () async {
      final adapter = _EchoAdapter()..extraResponseFields = {'event_id': 9};
      final client = ApiClient.test(tokenProvider: () async => null);
      client.debugDio.httpClientAdapter = adapter;
      final service = BookingService(client);
      final item = CartItem.fromListing(
        _ordinaryListing(),
        name: 'Ведущий',
        categoryLabel: 'Ведущие',
      );
      final result = await service.submitBooking(
        name: 'Айгерим',
        phone: '+77001234567',
        items: [item],
      );
      expect(result.booking.publicRef, 'abc123');
      expect(result.booking.eventId, 9);
      expect(result.booking.items, hasLength(1));
      expect(result.booking.total, 250000);
      expect(result.onboarding, isNull);
    },
  );
}
