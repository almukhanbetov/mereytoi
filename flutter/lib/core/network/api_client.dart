import 'package:dio/dio.dart';

import '../config/api_config.dart';
import 'api_exception.dart';

/// The one Dio instance for the whole app. Screens never call Dio directly —
/// they go through a Service (see lib/services/), which goes through this
/// client. Converts every failure into an [ApiException] so callers only
/// ever handle one error shape.
class ApiClient {
  ApiClient._internal()
      : _dio = Dio(
          BaseOptions(
            baseUrl: ApiConfig.baseUrl,
            connectTimeout: const Duration(seconds: 12),
            receiveTimeout: const Duration(seconds: 12),
            headers: {'Content-Type': 'application/json'},
          ),
        );

  static final ApiClient instance = ApiClient._internal();

  final Dio _dio;

  Future<Map<String, dynamic>> getJson(String path, {Map<String, dynamic>? query}) async {
    final res = await _run(() => _dio.get(path, queryParameters: query));
    return _asMap(res);
  }

  Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> body) async {
    final res = await _run(() => _dio.post(path, data: body));
    return _asMap(res);
  }

  Future<Response<dynamic>> _run(Future<Response<dynamic>> Function() request) async {
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
    throw const ApiException(ApiErrorType.unknown, debugMessage: 'response was not a JSON object');
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
          return ApiException(ApiErrorType.notFound, statusCode: status, debugMessage: e.message);
        }
        if (status != null && status >= 500) {
          return ApiException(ApiErrorType.server, statusCode: status, debugMessage: e.message);
        }
        return ApiException(ApiErrorType.unknown, statusCode: status, debugMessage: _extractServerError(e));
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
