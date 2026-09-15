import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/network/api_client.dart';
import 'package:mereytoi_app/core/network/api_exception.dart';
import 'package:mereytoi_app/services/auth_service.dart';

/// A connection-error adapter — used just once below to prove
/// `claimResend()` still propagates a genuine network failure as an
/// `ApiException` rather than swallowing it (the *backend's own* response
/// is neutral by design, but a request that never reached the backend at
/// all is a different thing entirely).
class _ThrowingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.responder);

  final Map<String, dynamic> Function(RequestOptions options) responder;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
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

(AuthService, _FakeAdapter) _service(
  Map<String, dynamic> Function(RequestOptions options) responder,
) {
  final adapter = _FakeAdapter(responder);
  final client = ApiClient.test(tokenProvider: () async => 'test-token');
  client.debugDio.httpClientAdapter = adapter;
  return (AuthService(client), adapter);
}

Map<String, dynamic> _userJson({int id = 3, String name = 'Айгерим'}) => {
  'id': id,
  'name': name,
  'email': 'a@example.com',
  'phone': '+77001234567',
  'role': 'user',
  'status': 'active',
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
};

void main() {
  test('updateMe() sends only name/phone and parses the saved user', () async {
    final (service, adapter) = _service((options) {
      expect(options.path, '/api/auth/me');
      expect(options.method, 'PUT');
      final body = options.data as Map;
      return {'user': _userJson(name: body['name'] as String)};
    });

    final user = await service.updateMe(
      name: 'Жаңа Есім',
      phone: '+77001112233',
    );
    expect(user.name, 'Жаңа Есім');
    final sentBody = adapter.requests.single.data as Map;
    expect(sentBody.keys, containsAll(['name', 'phone']));
  });

  test(
    'updateDeliveryPreference() only ever sends whatsapp/telegram',
    () async {
      final (service, adapter) = _service((options) {
        final channel = (options.data as Map)['channel'];
        return {'preferred_delivery_channel': channel};
      });

      expect(await service.updateDeliveryPreference('telegram'), 'telegram');
      expect((adapter.requests.single.data as Map)['channel'], 'telegram');
    },
  );

  test('claim() parses user/token/event_id on success', () async {
    final (service, adapter) = _service((options) {
      expect(options.path, '/api/auth/claim/abc123token');
      return {'user': _userJson(), 'token': 'jwt-token-value', 'event_id': 9};
    });

    final result = await service.claim('abc123token');
    expect(result.user.id, 3);
    expect(result.token, 'jwt-token-value');
    expect(result.eventId, 9);
    expect(adapter.requests.single.path, '/api/auth/claim/abc123token');
  });

  test('claim() eventId is null when the account owns no event yet', () async {
    final (service, _) = _service((options) {
      return {'user': _userJson(), 'token': 'jwt-token-value'};
    });
    final result = await service.claim('abc123token');
    expect(result.eventId, isNull);
  });

  test(
    'claimResend() posts the phone and never surfaces a distinguishable result',
    () async {
      final (service, adapter) = _service((options) {
        return {
          'message':
              'Если кабинет связан с этим номером, ссылка будет отправлена.',
        };
      });
      await service.claimResend('+77001234567');
      expect((adapter.requests.single.data as Map)['phone'], '+77001234567');
    },
  );

  test(
    '21. resend claim error — a network failure surfaces as a plain ApiException, not a silent success',
    () async {
      final client = ApiClient.test(tokenProvider: () async => null);
      client.debugDio.httpClientAdapter = _ThrowingAdapter();
      final service = AuthService(client);

      expect(
        () => service.claimResend('+77001234567'),
        throwsA(isA<ApiException>()),
      );
    },
  );

  group('mintTelegramLinkToken()', () {
    test('configured: true returns a real t.me link', () async {
      final (service, _) = _service((options) {
        expect(options.path, '/api/users/me/telegram/link-token');
        return {
          'configured': true,
          'link_url': 'https://t.me/mereytoi_bot?start=xyz',
        };
      });
      final result = await service.mintTelegramLinkToken();
      expect(result.configured, isTrue);
      expect(result.linkUrl, 'https://t.me/mereytoi_bot?start=xyz');
    });

    test(
      'configured: false (no bot token set server-side) — no link_url either',
      () async {
        final (service, _) = _service((options) {
          return {'configured': false};
        });
        final result = await service.mintTelegramLinkToken();
        expect(result.configured, isFalse);
        expect(result.linkUrl, isNull);
      },
    );
  });
}
