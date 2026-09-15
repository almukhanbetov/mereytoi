import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/network/api_client.dart';
import 'package:mereytoi_app/core/storage/token_storage.dart';
import 'package:mereytoi_app/state/auth_provider.dart';
import 'package:mereytoi_app/state/providers.dart';

/// An in-memory `FlutterSecureStoragePlatform` — `TokenStorage.instance`'s
/// own `FlutterSecureStorage()` reads `FlutterSecureStoragePlatform.instance`
/// lazily on every call, so swapping this static field in `setUp` is
/// enough to make real `saveToken`/`readToken`/`clearToken` calls work
/// against a fake store, no raw platform-channel mocking needed.
class _FakeSecureStoragePlatform extends FlutterSecureStoragePlatform {
  final Map<String, String> _store = {};

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) => Future.value(_store.containsKey(key));

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    _store.remove(key);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    _store.clear();
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) => Future.value(_store[key]);

  @override
  Future<Map<String, String>> readAll({required Map<String, String> options}) =>
      Future.value(Map.of(_store));

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    _store[key] = value;
  }
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.responder);

  final Map<String, dynamic> Function(RequestOptions options) responder;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final data = responder(options);
    final body = Uint8List.fromList(utf8.encode(jsonEncode(data)));
    return ResponseBody.fromBytes(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _userJson({String name = 'Айгерим'}) => {
  'id': 3,
  'name': name,
  'email': 'a@example.com',
  'phone': '',
  'role': 'user',
  'status': 'active',
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
};

void main() {
  late _FakeSecureStoragePlatform fakeSecureStorage;

  setUp(() {
    fakeSecureStorage = _FakeSecureStoragePlatform();
    FlutterSecureStoragePlatform.instance = fakeSecureStorage;
  });

  ProviderContainer containerWithFakeBackend(
    Map<String, dynamic> Function(RequestOptions options) responder,
  ) {
    final client = ApiClient.test(
      tokenProvider: TokenStorage.instance.readToken,
    );
    client.debugDio.httpClientAdapter = _FakeAdapter(responder);
    return ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(client)],
    );
  }

  test(
    'claim() saves the token to secure storage and lands on AuthAuthenticated',
    () async {
      final container = containerWithFakeBackend((options) {
        return {'user': _userJson(), 'token': 'claimed-jwt', 'event_id': 9};
      });
      addTearDown(container.dispose);

      final eventId = await container
          .read(authProvider.notifier)
          .claim('sometoken');

      expect(eventId, 9);
      expect(container.read(authProvider), isA<AuthAuthenticated>());
      expect(await TokenStorage.instance.readToken(), 'claimed-jwt');
    },
  );

  test(
    'updateProfile() carries telegram_linked/preferred_delivery_channel over from the current session',
    () async {
      final container = containerWithFakeBackend((options) {
        final body = options.data as Map?;
        if (options.path == '/api/auth/login') {
          return {'user': _userJson(), 'token': 'login-jwt'};
        }
        return {'user': _userJson(name: body?['name'] as String? ?? 'X')};
      });
      addTearDown(container.dispose);

      await container
          .read(authProvider.notifier)
          .login(email: 'a@example.com', password: 'x');
      final beforeState = container.read(authProvider) as AuthAuthenticated;
      // Simulate a prior GET /api/auth/me having already set these two
      // /me-only sibling fields (see User's own doc comment) — updateProfile
      // must not silently null them back out.
      final seeded = beforeState.user.copyWith(
        telegramLinked: true,
        preferredDeliveryChannel: 'telegram',
      );
      container.read(authProvider.notifier).state = AuthAuthenticated(seeded);

      await container
          .read(authProvider.notifier)
          .updateProfile(name: 'Жаңа Есім');

      final after = container.read(authProvider) as AuthAuthenticated;
      expect(after.user.name, 'Жаңа Есім');
      expect(after.user.telegramLinked, isTrue);
      expect(after.user.preferredDeliveryChannel, 'telegram');
    },
  );

  test(
    'updateDeliveryPreference() updates the current session state in place',
    () async {
      final container = containerWithFakeBackend((options) {
        if (options.path == '/api/auth/login') {
          return {'user': _userJson(), 'token': 'login-jwt'};
        }
        return {'preferred_delivery_channel': (options.data as Map)['channel']};
      });
      addTearDown(container.dispose);

      await container
          .read(authProvider.notifier)
          .login(email: 'a@example.com', password: 'x');
      await container
          .read(authProvider.notifier)
          .updateDeliveryPreference('whatsapp');

      final state = container.read(authProvider) as AuthAuthenticated;
      expect(state.user.preferredDeliveryChannel, 'whatsapp');
    },
  );

  test(
    'logout() clears the secure-stored token and lands on AuthUnauthenticated',
    () async {
      final container = containerWithFakeBackend((options) {
        return {'user': _userJson(), 'token': 'login-jwt'};
      });
      addTearDown(container.dispose);

      await container
          .read(authProvider.notifier)
          .login(email: 'a@example.com', password: 'x');
      expect(await TokenStorage.instance.readToken(), 'login-jwt');

      await container.read(authProvider.notifier).logout();

      expect(container.read(authProvider), isA<AuthUnauthenticated>());
      expect(await TokenStorage.instance.readToken(), isNull);
    },
  );
}
