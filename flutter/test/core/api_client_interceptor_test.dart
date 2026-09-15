import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/network/api_client.dart';

/// A fake transport that never touches the network — it just records the
/// last [RequestOptions] the interceptor chain produced and always
/// answers with an empty JSON object, so `ApiClient.getJson` completes
/// normally and the test can then inspect exactly what headers were sent.
class _RecordingAdapter implements HttpClientAdapter {
  RequestOptions? lastOptions;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastOptions = options;
    final body = Uint8List.fromList('{}'.codeUnits);
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

void main() {
  group('ApiClient Authorization interceptor', () {
    test(
      'attaches "Authorization: Bearer <token>" when a token exists',
      () async {
        final adapter = _RecordingAdapter();
        final client = ApiClient.test(tokenProvider: () async => 'abc123');
        client.debugDio.httpClientAdapter = adapter;

        await client.getJson('/api/auth/me');

        expect(adapter.lastOptions?.headers['Authorization'], 'Bearer abc123');
      },
    );

    test(
      'sends no Authorization header at all when there is no token (guest request)',
      () async {
        final adapter = _RecordingAdapter();
        final client = ApiClient.test(tokenProvider: () async => null);
        client.debugDio.httpClientAdapter = adapter;

        await client.getJson('/api/listings');

        expect(
          adapter.lastOptions?.headers.containsKey('Authorization'),
          isFalse,
        );
      },
    );

    test('an empty-string token is also treated as "no token"', () async {
      final adapter = _RecordingAdapter();
      final client = ApiClient.test(tokenProvider: () async => '');
      client.debugDio.httpClientAdapter = adapter;

      await client.getJson('/api/listings');

      expect(
        adapter.lastOptions?.headers.containsKey('Authorization'),
        isFalse,
      );
    });

    test(
      'a 401 response triggers the unauthorized handler exactly once, and the caller still gets its ApiException',
      () async {
        var calls = 0;
        final adapter = _Recording401Adapter();
        final client = ApiClient.test(tokenProvider: () async => 'stale-token');
        client.debugDio.httpClientAdapter = adapter;
        client.setUnauthorizedHandler(() => calls++);

        await expectLater(
          client.getJson('/api/auth/me'),
          throwsA(isA<Exception>()),
        );

        expect(calls, 1);
      },
    );
  });
}

class _Recording401Adapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = Uint8List.fromList(
      '{"error":"invalid or expired token"}'.codeUnits,
    );
    return ResponseBody.fromBytes(
      body,
      401,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
