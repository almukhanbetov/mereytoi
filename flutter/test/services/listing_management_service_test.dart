import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/network/api_client.dart';
import 'package:mereytoi_app/services/listing_management_service.dart';

/// Same fake-adapter seam every other service test in this suite uses —
/// echoes back whatever was sent under the envelope key the real handler
/// actually uses (`hall`/`menu`/`section`/`item`/`extra`), so these tests
/// assert on the *request* payload shape against the real backend
/// contracts confirmed directly in `backend/internal/handlers/
/// listing_hall_handler.go` and `listing_menu_handler.go` before writing
/// this service.
class _EchoAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.method == 'DELETE') {
      return ResponseBody.fromBytes(
        Uint8List.fromList(utf8.encode(jsonEncode({'message': 'deleted'}))),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    final body = Map<String, dynamic>.from(options.data as Map);
    final Map<String, dynamic> data;
    if (options.path.endsWith('/halls') || options.path.contains('/halls/')) {
      data = {
        'hall': {'id': 1, 'listing_id': 48, ...body},
      };
    } else if (options.path.contains('/sections/') &&
        options.path.contains('/items')) {
      data = {
        'item': {'id': 1, 'section_id': 1, ...body},
      };
    } else if (options.path.contains('/extras')) {
      data = {
        'extra': {'id': 1, 'menu_id': 1, ...body},
      };
    } else if (options.path.contains('/sections')) {
      data = {
        'section': {'id': 1, 'menu_id': 1, ...body},
      };
    } else if (options.path.endsWith('/menus') ||
        RegExp(r'/menus/\d+$').hasMatch(options.path)) {
      data = {
        'menu': {'id': 1, 'listing_id': 48, ...body},
      };
    } else {
      data = {
        'listing': {'id': 48, ...body},
      };
    }
    return ResponseBody.fromBytes(
      Uint8List.fromList(utf8.encode(jsonEncode(data))),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

(ListingManagementService, _EchoAdapter) _service() {
  final adapter = _EchoAdapter();
  final client = ApiClient.test(tokenProvider: () async => 'admin-token');
  client.debugDio.httpClientAdapter = adapter;
  return (ListingManagementService(client), adapter);
}

void main() {
  group('halls', () {
    test('createHall() posts the exact listingHallInput shape', () async {
      final (service, adapter) = _service();
      await service.createHall(
        48,
        nameRu: 'Зал А',
        nameKz: 'А залы',
        capacity: 100,
        price: 0,
        isActive: true,
        sortOrder: 0,
      );
      expect(adapter.requests.single.path, '/api/listings/48/halls');
      expect(adapter.requests.single.method, 'POST');
      final body = adapter.requests.single.data as Map;
      expect(
        body.keys,
        containsAll([
          'name_ru',
          'name_kz',
          'description_ru',
          'description_kz',
          'capacity',
          'price',
          'image_urls',
          'is_active',
          'sort_order',
        ]),
      );
      expect(body['capacity'], 100);
    });

    test('updateHall() PUTs to :id/halls/:hallId', () async {
      final (service, adapter) = _service();
      await service.updateHall(
        48,
        1,
        nameRu: 'Зал А',
        nameKz: 'А залы',
        capacity: 120,
        isActive: false,
      );
      expect(adapter.requests.single.path, '/api/listings/48/halls/1');
      expect(adapter.requests.single.method, 'PUT');
      expect((adapter.requests.single.data as Map)['is_active'], isFalse);
    });

    test('deleteHall() DELETEs to :id/halls/:hallId', () async {
      final (service, adapter) = _service();
      await service.deleteHall(48, 1);
      expect(adapter.requests.single.path, '/api/listings/48/halls/1');
      expect(adapter.requests.single.method, 'DELETE');
    });
  });

  group('menus', () {
    test('createMenu() posts the exact listingMenuInput shape', () async {
      final (service, adapter) = _service();
      await service.createMenu(
        48,
        hallId: 1,
        nameRu: 'Меню 1',
        nameKz: 'Мәзір 1',
        pricePerGuest: 25000,
        minGuests: 50,
        maxGuests: 120,
      );
      expect(adapter.requests.single.path, '/api/listings/48/menus');
      final body = adapter.requests.single.data as Map;
      expect(body['hall_id'], 1);
      expect(body['price_per_guest'], 25000);
      expect(body['min_guests'], 50);
      expect(body['max_guests'], 120);
      expect(body.containsKey('valid_from'), isTrue);
      expect(body.containsKey('valid_until'), isTrue);
    });

    test('updateMenu() PUTs to :id/menus/:menuId', () async {
      final (service, adapter) = _service();
      await service.updateMenu(
        48,
        1,
        nameRu: 'Меню 1',
        nameKz: 'Мәзір 1',
        pricePerGuest: 30000,
      );
      expect(adapter.requests.single.path, '/api/listings/48/menus/1');
      expect(adapter.requests.single.method, 'PUT');
    });

    test('deleteMenu() DELETEs to :id/menus/:menuId', () async {
      final (service, adapter) = _service();
      await service.deleteMenu(48, 1);
      expect(adapter.requests.single.path, '/api/listings/48/menus/1');
      expect(adapter.requests.single.method, 'DELETE');
    });
  });

  group('sections/items/extras', () {
    test(
      'createSection() only sends title_ru/title_kz/sort_order — no invented fields',
      () async {
        final (service, adapter) = _service();
        await service.createSection(
          48,
          1,
          titleRu: 'Закуски',
          titleKz: 'Тағамдар',
        );
        expect(
          adapter.requests.single.path,
          '/api/listings/48/menus/1/sections',
        );
        final body = adapter.requests.single.data as Map;
        expect(body.keys.toSet(), {'title_ru', 'title_kz', 'sort_order'});
      },
    );

    test(
      'createItem() posts to the nested sections/:sectionId/items path',
      () async {
        final (service, adapter) = _service();
        await service.createItem(
          48,
          1,
          1,
          nameRu: 'Мясное ассорти',
          nameKz: 'Ет ассортиси',
          quantityText: '250 г',
        );
        expect(
          adapter.requests.single.path,
          '/api/listings/48/menus/1/sections/1/items',
        );
        expect((adapter.requests.single.data as Map)['quantity_text'], '250 г');
      },
    );

    test(
      'createExtra() posts type/unit exactly as given, no coercion',
      () async {
        final (service, adapter) = _service();
        await service.createExtra(
          48,
          1,
          type: 'kids_table',
          titleRu: 'Детский стол',
          titleKz: 'Балалар үстелі',
          price: 12000,
          unit: 'per_guest',
        );
        expect(adapter.requests.single.path, '/api/listings/48/menus/1/extras');
        final body = adapter.requests.single.data as Map;
        expect(body['type'], 'kids_table');
        expect(body['unit'], 'per_guest');
        expect(
          body.containsKey('is_active'),
          isFalse,
        ); // no such field on the backend
      },
    );
  });

  test('every write sends the admin Bearer token', () async {
    final (service, adapter) = _service();
    await service.createHall(48, nameRu: 'A', nameKz: 'A');
    expect(
      adapter.requests.single.headers['Authorization'],
      'Bearer admin-token',
    );
  });
}
