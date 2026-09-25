import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/network/api_client.dart';
import 'package:mereytoi_app/state/listings_provider.dart';
import 'package:mereytoi_app/state/provider_provider.dart';
import 'package:mereytoi_app/state/providers.dart';

/// Stateful fake backend for the Этап 11 provider marketplace endpoints —
/// same "mutations actually change what a subsequent read returns" style
/// `listing_management_actions_test.dart` already established.
class _FakeProviderBackend implements HttpClientAdapter {
  Map<String, dynamic>? provider;
  final List<Map<String, dynamic>> listings = [];
  int _nextListingId = 1;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final (status, data) = _handle(options);
    return ResponseBody.fromBytes(
      Uint8List.fromList(utf8.encode(jsonEncode(data))),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  (int, Map<String, dynamic>) _handle(RequestOptions options) {
    if (options.method == 'GET' && options.path == '/api/provider/me') {
      if (provider == null) return (404, {'error': 'no provider profile'});
      return (200, {'provider': provider});
    }
    if (options.method == 'POST' && options.path == '/api/provider') {
      if (provider != null) {
        return (409, {'error': 'provider profile already exists'});
      }
      final body = Map<String, dynamic>.from(options.data as Map);
      provider = {'id': 1, 'user_id': 9, 'status': 'active', ...body};
      return (201, {'provider': provider});
    }
    if (options.method == 'PUT' && options.path == '/api/provider/me') {
      final body = Map<String, dynamic>.from(options.data as Map);
      provider = {...provider!, ...body};
      return (200, {'provider': provider});
    }
    if (options.method == 'POST' &&
        options.path == '/api/provider/me/listings') {
      final body = Map<String, dynamic>.from(options.data as Map);
      final listing = {
        'id': _nextListingId++,
        'is_active': true,
        'role': 'owner',
        ...body,
      };
      listings.add(listing);
      return (201, {'listing': listing});
    }
    if (options.method == 'GET' && options.path == '/api/users/me/listings') {
      return (200, {'listings': listings});
    }
    if (options.method == 'PUT' &&
        options.path.startsWith('/api/listings/')) {
      final id = int.parse(options.path.split('/').last);
      final body = Map<String, dynamic>.from(options.data as Map);
      final idx = listings.indexWhere((l) => l['id'] == id);
      listings[idx] = {...listings[idx], ...body};
      return (200, {'listing': listings[idx]});
    }
    if (options.method == 'DELETE' &&
        options.path.startsWith('/api/listings/')) {
      final id = int.parse(options.path.split('/').last);
      listings.removeWhere((l) => l['id'] == id);
      return (200, {'message': 'listing deleted'});
    }
    throw StateError('unhandled fake route: ${options.method} ${options.path}');
  }

  @override
  void close({bool force = false}) {}
}

ProviderContainer _containerWithFakeBackend(_FakeProviderBackend backend) {
  final client = ApiClient.test(tokenProvider: () async => 'user-token');
  client.debugDio.httpClientAdapter = backend;
  return ProviderContainer(
    overrides: [apiClientProvider.overrideWithValue(client)],
  );
}

void main() {
  test(
    'providerProfileProvider resolves to null (not an error) when the caller has no profile yet',
    () async {
      final container = _containerWithFakeBackend(_FakeProviderBackend());
      addTearDown(container.dispose);

      final result = await container.read(providerProfileProvider.future);
      expect(result, isNull);
    },
  );

  test(
    'become() creates the profile — providerProfileProvider reflects it once invalidated',
    () async {
      final container = _containerWithFakeBackend(_FakeProviderBackend());
      addTearDown(container.dispose);

      expect(await container.read(providerProfileProvider.future), isNull);

      await container
          .read(providerActionsProvider)
          .become(displayName: 'Aigerim MC', city: 'Алматы');

      final provider = await container.read(providerProfileProvider.future);
      expect(provider, isNotNull);
      expect(provider!.displayName, 'Aigerim MC');
      expect(provider.city, 'Алматы');
      expect(
        provider.status,
        'active',
        reason: 'a self-serve profile lands directly on active — no moderation UI this stage',
      );
    },
  );

  test('updateProfile() changes the existing profile in place', () async {
    final backend = _FakeProviderBackend();
    final container = _containerWithFakeBackend(backend);
    addTearDown(container.dispose);

    await container.read(providerActionsProvider).become(displayName: 'Old Name');
    await container
        .read(providerActionsProvider)
        .updateProfile(displayName: 'New Name', city: 'Астана');

    final provider = await container.read(providerProfileProvider.future);
    expect(provider!.displayName, 'New Name');
    expect(provider.city, 'Астана');
  });

  test(
    'createListing() shows up in myListingsProvider — the reused Мои услуги/Мои рестораны list',
    () async {
      final container = _containerWithFakeBackend(_FakeProviderBackend());
      addTearDown(container.dispose);

      expect(await container.read(myListingsProvider.future), isEmpty);

      await container
          .read(providerActionsProvider)
          .createListing(
            categoryId: 2,
            nameRu: 'Ведущая Айгерим',
            nameKz: 'Жүргізуші Айгерім',
            price: 150000,
            priceType: 'per_event',
          );

      final listings = await container.read(myListingsProvider.future);
      expect(listings, hasLength(1));
      expect(listings.single.nameRu, 'Ведущая Айгерим');
      expect(listings.single.priceType, 'per_event');
    },
  );

  test('updateListing() can toggle publication (is_active) off and on', () async {
    final container = _containerWithFakeBackend(_FakeProviderBackend());
    addTearDown(container.dispose);

    await container
        .read(providerActionsProvider)
        .createListing(categoryId: 2, nameRu: 'Услуга', nameKz: 'Қызмет');
    final created = (await container.read(myListingsProvider.future)).single;
    expect(created.isActive, isTrue);

    await container
        .read(providerActionsProvider)
        .updateListing(
          created,
          nameRu: created.nameRu,
          nameKz: created.nameKz,
          isActive: false,
        );

    final afterToggle = (await container.read(myListingsProvider.future)).single;
    expect(afterToggle.isActive, isFalse);
  });

  test('deleteListing() removes it from Мои услуги', () async {
    final container = _containerWithFakeBackend(_FakeProviderBackend());
    addTearDown(container.dispose);

    await container
        .read(providerActionsProvider)
        .createListing(categoryId: 2, nameRu: 'Услуга', nameKz: 'Қызмет');
    final created = (await container.read(myListingsProvider.future)).single;

    await container.read(providerActionsProvider).deleteListing(created.id);

    expect(await container.read(myListingsProvider.future), isEmpty);
  });
}
