import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/network/api_client.dart';
import 'package:mereytoi_app/core/network/api_exception.dart';
import 'package:mereytoi_app/core/storage/token_storage.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/core/utils/error_messages.dart';
import 'package:mereytoi_app/state/locale_provider.dart';
import 'package:mereytoi_app/widgets/app_error_view.dart';

// Play 1.0.1 (2) on a tester's phone: «Не удалось загрузить данные» on
// every screen while Chrome on the same phone loaded the API fine.
// Reproduced on a POCO: Android restored flutter_secure_storage's prefs
// from a Google backup onto the reinstall without the Keystore key, so
// every token read threw PlatformException(BadPaddingException) — inside
// the request interceptor, failing every request before it was sent.

/// Secure storage whose reads fail the way a restored, undecryptable
/// store does.
class _CorruptedStorage extends FlutterSecureStoragePlatform {
  int deleteAllCalls = 0;

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) => Future.error(
    PlatformException(
      code: 'Exception encountered',
      message: 'read',
      details: 'javax.crypto.BadPaddingException: error:1e000065',
    ),
  );

  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      deleteAllCalls++;

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => false;
  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {}
  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => const {};
  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {}
}

/// Answers every request with [status]/[body], or throws [error].
class _Adapter implements HttpClientAdapter {
  _Adapter({this.status = 200, this.body = '{}', this.error, this.type});

  final int status;
  final String body;
  final Object? error;
  final String? type;
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    last = options;
    if (error != null) throw error!;
    return ResponseBody.fromBytes(
      utf8.encode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [type ?? Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<Object> _failure(_Adapter adapter) async {
  final client = ApiClient.test(tokenProvider: () async => null);
  client.debugDio.httpClientAdapter = adapter;
  try {
    await client.getJson('/api/listings');
  } catch (e) {
    return e;
  }
  fail('request unexpectedly succeeded');
}

void main() {
  group('unreadable token storage (the 1.0.1 defect)', () {
    test('readToken resets the store and reads as "no session"', () async {
      final platform = _CorruptedStorage();
      FlutterSecureStoragePlatform.instance = platform;
      final storage = TokenStorage.test(const FlutterSecureStorage());
      expect(await storage.readToken(), isNull);
      expect(platform.deleteAllCalls, 1);
    });

    test('a token provider that throws no longer fails the request', () async {
      final adapter = _Adapter(body: '{"listings":[]}');
      final client = ApiClient.test(
        tokenProvider: () =>
            Future.error(PlatformException(code: 'Exception encountered')),
      );
      client.debugDio.httpClientAdapter = adapter;
      final json = await client.getJson('/api/listings');
      expect(json['listings'], isEmpty);
      expect(adapter.last?.headers.containsKey('Authorization'), isFalse);
    });
  });

  group('failures are told apart', () {
    const ru = AppLocale.ru;

    test('no network', () async {
      final e = await _failure(
        _Adapter(error: const SocketException('Failed host lookup')),
      );
      expect(apiErrorMessage(ru, e), 'Нет подключения к интернету');
      expect(errorDiagnostics(e), startsWith('ERR_NETWORK'));
    });

    test('TLS handshake failure', () async {
      final e = await _failure(
        _Adapter(error: const HandshakeException('CERTIFICATE_VERIFY_FAILED')),
      );
      expect(
        e,
        isA<ApiException>().having((x) => x.type, 'type', ApiErrorType.tls),
      );
      expect(
        apiErrorMessage(ru, e),
        'Не удалось установить защищённое соединение',
      );
      expect(errorDiagnostics(e), 'ERR_TLS · HandshakeException');
    });

    test('server error keeps its HTTP status', () async {
      final e = await _failure(_Adapter(status: 502, body: '{}'));
      expect(apiErrorMessage(ru, e), 'Сервис временно недоступен');
      expect(errorDiagnostics(e), startsWith('ERR_HTTP_502'));
    });

    test('an unusual 4xx shows its status code', () async {
      final e = await _failure(
        _Adapter(status: 429, body: '{"error":"too many requests"}'),
      );
      expect(errorDiagnostics(e), startsWith('ERR_HTTP_429'));
    });

    test('an HTML page instead of JSON is an invalid response', () async {
      final e = await _failure(
        _Adapter(body: '<html>Wi-Fi login</html>', type: 'text/html'),
      );
      expect(apiErrorMessage(ru, e), 'Сервер вернул некорректный ответ');
      expect(errorDiagnostics(e), startsWith('ERR_FORMAT'));
    });

    test('a model that cannot parse the response is not "no internet"', () {
      Object? e;
      try {
        // ignore: unused_local_variable
        final int bad = (jsonDecode('{"id":"x"}') as Map)['id'] as int;
      } catch (err) {
        e = err;
      }
      expect(apiErrorMessage(ru, e!), 'Не удалось обработать ответ сервера');
      expect(errorDiagnostics(e), startsWith('ERR_TYPE'));
    });

    test('a storage error surfaced through the API is ERR_STORAGE', () {
      const e = ApiException(
        ApiErrorType.unknown,
        causeType: 'PlatformException',
      );
      expect(errorDiagnostics(e), 'ERR_STORAGE · PlatformException');
    });
  });

  testWidgets('AppErrorView shows the diagnostic line under the message', (
    tester,
  ) async {
    const error = ApiException(
      ApiErrorType.unknown,
      statusCode: 418,
      causeType: 'DioException',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: AppErrorView(
            message: apiErrorMessage(AppLocale.ru, error),
            locale: AppLocale.ru,
            onRetry: () {},
            error: error,
          ),
        ),
      ),
    );
    expect(find.text('Не удалось загрузить данные'), findsOneWidget);
    expect(find.text('ERR_HTTP_418 · DioException'), findsOneWidget);
  });
}
