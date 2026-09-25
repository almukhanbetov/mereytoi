import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/network/api_client.dart';
import 'package:mereytoi_app/state/listing_management_actions.dart';
import 'package:mereytoi_app/state/listings_provider.dart';
import 'package:mereytoi_app/state/providers.dart';

/// A stateful fake backend — same "mutations actually change what a
/// subsequent read returns" style `notification_actions_test.dart`
/// already established. Proves the brief's own requirement directly:
/// after `createHall`/`createMenu`, [listingHallsProvider]/
/// [listingMenusProvider] — the exact two providers the *public*
/// `RestaurantDetailScreen` watches — see the new row with no app
/// restart, purely from Riverpod's own invalidate-and-refetch.
class _FakeRestaurantBackend implements HttpClientAdapter {
  final List<Map<String, dynamic>> halls = [];
  final List<Map<String, dynamic>> menus = [];
  int _nextHallId = 1;
  int _nextMenuId = 1;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final data = _handle(options);
    return ResponseBody.fromBytes(
      Uint8List.fromList(utf8.encode(jsonEncode(data))),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  Map<String, dynamic> _handle(RequestOptions options) {
    if (options.method == 'GET' && options.path == '/api/listings/48/halls') {
      return {'halls': halls};
    }
    if (options.method == 'GET' && options.path == '/api/listings/48/menus') {
      return {'menus': menus};
    }
    if (options.method == 'GET' && options.path == '/api/listings/48') {
      return {
        'listing': {'id': 48, 'category_id': 1, 'halls': halls, 'menus': menus},
      };
    }
    if (options.method == 'POST' && options.path == '/api/listings/48/halls') {
      final body = Map<String, dynamic>.from(options.data as Map);
      final hall = {
        'id': _nextHallId++,
        'listing_id': 48,
        'is_active': true,
        ...body,
      };
      halls.add(hall);
      return {'hall': hall};
    }
    if (options.method == 'POST' && options.path == '/api/listings/48/menus') {
      final body = Map<String, dynamic>.from(options.data as Map);
      final menu = {
        'id': _nextMenuId++,
        'listing_id': 48,
        'is_active': true,
        ...body,
      };
      menus.add(menu);
      return {'menu': menu};
    }
    throw StateError('unhandled fake route: ${options.method} ${options.path}');
  }

  @override
  void close({bool force = false}) {}
}

ProviderContainer _containerWithFakeBackend(_FakeRestaurantBackend backend) {
  final client = ApiClient.test(tokenProvider: () async => 'admin-token');
  client.debugDio.httpClientAdapter = backend;
  return ProviderContainer(
    overrides: [apiClientProvider.overrideWithValue(client)],
  );
}

void main() {
  test(
    'createHall() invalidates listingHallsProvider — the public RestaurantDetailScreen '
    'sees the new hall on its next rebuild, no restart needed',
    () async {
      final container = _containerWithFakeBackend(_FakeRestaurantBackend());
      addTearDown(container.dispose);

      expect(await container.read(listingHallsProvider(48).future), isEmpty);

      await container
          .read(listingManagementActionsProvider)
          .createHall(48, nameRu: 'Зал А', nameKz: 'А залы', capacity: 100);

      final halls = await container.read(listingHallsProvider(48).future);
      expect(halls, hasLength(1));
      expect(halls.single.nameRu, 'Зал А');
    },
  );

  test('createMenu() invalidates listingMenusProvider the same way', () async {
    final container = _containerWithFakeBackend(_FakeRestaurantBackend());
    addTearDown(container.dispose);

    expect(await container.read(listingMenusProvider(48).future), isEmpty);

    await container
        .read(listingManagementActionsProvider)
        .createMenu(
          48,
          nameRu: 'Меню 1',
          nameKz: 'Мәзір 1',
          pricePerGuest: 25000,
        );

    final menus = await container.read(listingMenusProvider(48).future);
    expect(menus, hasLength(1));
    expect(menus.single.pricePerGuest, 25000);
  });

  test(
    'createHall() also invalidates listingAllHallsProvider (the management-only, unfiltered read)',
    () async {
      final container = _containerWithFakeBackend(_FakeRestaurantBackend());
      addTearDown(container.dispose);

      expect(await container.read(listingAllHallsProvider(48).future), isEmpty);

      await container
          .read(listingManagementActionsProvider)
          .createHall(48, nameRu: 'Зал Б', nameKz: 'Б залы');

      final halls = await container.read(listingAllHallsProvider(48).future);
      expect(halls, hasLength(1));
    },
  );
}
