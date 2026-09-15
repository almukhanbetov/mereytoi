import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/api_config.dart';
import '../storage/token_storage.dart';
import 'api_exception.dart';

/// The one Dio instance for the whole app. Screens never call Dio directly —
/// they go through a Service (see lib/services/), which goes through this
/// client. Converts every failure into an [ApiException] so callers only
/// ever handle one error shape.
///
/// Also owns the one Authorization interceptor for the whole app (Stage 1):
/// every request gets `Authorization: Bearer <token>` attached automatically
/// when a session token exists — no Service method attaches it by hand, and
/// a guest request (no token yet) is sent exactly as before, unchanged. A
/// 401 response — the token was rejected/expired — triggers [_onUnauthorized]
/// once; it never retries the request itself, so there is no retry loop to
/// worry about.
class ApiClient {
  ApiClient._internal({required this._tokenProvider})
    : _dio = Dio(
        BaseOptions(
          baseUrl: ApiConfig.baseUrl,
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 12),
          headers: {'Content-Type': 'application/json'},
        ),
      ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _tokenProvider();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) {
          if (error.response?.statusCode == 401) {
            _onUnauthorized?.call();
          }
          // Always forwarded, never swallowed here — the caller (a Service)
          // still gets its usual ApiException via `_run`'s own catch below.
          handler.next(error);
        },
      ),
    );
  }

  static final ApiClient instance = ApiClient._internal(
    tokenProvider: TokenStorage.instance.readToken,
  );

  /// Test-only: a client wired to a fake token source instead of the real
  /// secure-storage singleton, so the Authorization-header behavior can be
  /// unit-tested without a platform channel. Never used outside `test/`.
  @visibleForTesting
  factory ApiClient.test({required Future<String?> Function() tokenProvider}) {
    return ApiClient._internal(tokenProvider: tokenProvider);
  }

  final Dio _dio;

  /// Test-only seam: lets a test swap in a fake `HttpClientAdapter` (see
  /// test/core/api_client_interceptor_test.dart) to inspect the exact
  /// request the interceptor above produced, with no real network call and
  /// no platform channel involved.
  @visibleForTesting
  Dio get debugDio => _dio;
  final Future<String?> Function() _tokenProvider;
  VoidCallback? _onUnauthorized;

  /// Wired once by [AuthNotifier] at startup — kept as a plain callback
  /// (not a Riverpod `Ref`) so this network layer never depends on the
  /// state-management layer; it only ever reports "a request came back
  /// 401", never decides what that should mean for app state.
  void setUnauthorizedHandler(VoidCallback handler) =>
      _onUnauthorized = handler;

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final res = await _run(() => _dio.get(path, queryParameters: query));
    return _asMap(res);
  }

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final res = await _run(() => _dio.post(path, data: body));
    return _asMap(res);
  }

  /// Stage 4 (Event Workspace) — the first callers that need PUT (updating
  /// an event/candidate/task/member/request) rather than just GET/POST.
  Future<Map<String, dynamic>> putJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final res = await _run(() => _dio.put(path, data: body));
    return _asMap(res);
  }

  /// Stage 4 — deleting an event/candidate/comment/task/member/invitation.
  Future<Map<String, dynamic>> deleteJson(String path) async {
    final res = await _run(() => _dio.delete(path));
    return _asMap(res);
  }

  Future<Response<dynamic>> _run(
    Future<Response<dynamic>> Function() request,
  ) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Map<String, dynamic> _asMap(Response<dynamic> res) {
    final data = res.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw const ApiException(
      ApiErrorType.unknown,
      debugMessage: 'response was not a JSON object',
    );
  }

  ApiException _mapError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException(ApiErrorType.timeout, debugMessage: e.message);
      case DioExceptionType.connectionError:
        return ApiException(ApiErrorType.network, debugMessage: e.message);
      case DioExceptionType.badResponse:
        final status = e.response?.statusCode;
        if (status == 404) {
          return ApiException(
            ApiErrorType.notFound,
            statusCode: status,
            debugMessage: e.message,
          );
        }
        if (status == 403) {
          // Event Workspace's own role checks (e.g. "you can only remove
          // candidates you added", "insufficient role") — the first place
          // this app hits a 403 on a request that otherwise looked valid.
          return ApiException(
            ApiErrorType.forbidden,
            statusCode: status,
            debugMessage: _extractServerError(e),
          );
        }
        if (status == 410) {
          // POST /api/auth/claim/:token's own "already used"/"expired" —
          // the exact reason lives only in the message text (no separate
          // error code), so the claim screen distinguishes them itself.
          return ApiException(
            ApiErrorType.gone,
            statusCode: status,
            debugMessage: _extractServerError(e),
          );
        }
        if (status == 401) {
          // Covers both "wrong credentials" (POST /api/auth/login|register)
          // and "session token rejected/expired" (any authenticated call) —
          // the interceptor above already handles the session side-effect;
          // this is only the error surfaced back to the caller/UI.
          return ApiException(
            ApiErrorType.unauthorized,
            statusCode: status,
            debugMessage: _extractServerError(e),
          );
        }
        if (status == 409) {
          // POST /api/auth/register's own "email already registered" —
          // the one 409 this app currently produces.
          return ApiException(
            ApiErrorType.conflict,
            statusCode: status,
            debugMessage: _extractServerError(e),
          );
        }
        if (status != null && status >= 500) {
          return ApiException(
            ApiErrorType.server,
            statusCode: status,
            debugMessage: e.message,
          );
        }
        return ApiException(
          ApiErrorType.unknown,
          statusCode: status,
          debugMessage: _extractServerError(e),
        );
      default:
        return ApiException(ApiErrorType.unknown, debugMessage: e.message);
    }
  }

  String? _extractServerError(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] is String) return data['error'] as String;
    return e.message;
  }
}
