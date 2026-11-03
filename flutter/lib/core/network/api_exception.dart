/// Broad failure category — kept locale-free here (RU/KZ text lives in
/// core/utils/app_strings.dart) so a screen can show a bilingual message
/// instead of a raw Dio/HTTP exception or stack trace.
enum ApiErrorType {
  network,
  timeout,
  notFound,
  unauthorized,
  forbidden,
  gone,
  conflict,
  server,

  /// The TLS handshake failed (certificate not trusted, clock wrong, …).
  tls,

  /// A response arrived but wasn't the JSON object the API always sends
  /// (an HTML page from a proxy/captive portal, an empty body, …).
  invalidResponse,
  unknown,
}

class ApiException implements Exception {
  const ApiException(
    this.type, {
    this.statusCode,
    this.debugMessage,
    this.causeType,
  });

  final ApiErrorType type;
  final int? statusCode;
  final String? debugMessage;

  /// runtimeType of the underlying error (e.g. "PlatformException",
  /// "HandshakeException") — a type name only, never its message, so it is
  /// safe to show on screen and in logs.
  final String? causeType;

  /// Short code shown under the friendly message so a tester's screenshot
  /// tells which failure it was: `ERR_HTTP_<status>`, ERR_TIMEOUT,
  /// ERR_NETWORK, ERR_TLS, ERR_FORMAT, ERR_STORAGE, ERR_UNKNOWN.
  String get diagnosticCode {
    switch (type) {
      case ApiErrorType.network:
        return 'ERR_NETWORK';
      case ApiErrorType.timeout:
        return 'ERR_TIMEOUT';
      case ApiErrorType.tls:
        return 'ERR_TLS';
      case ApiErrorType.invalidResponse:
        return 'ERR_FORMAT';
      default:
        if (statusCode != null) return 'ERR_HTTP_$statusCode';
        if (causeType == 'PlatformException') return 'ERR_STORAGE';
        return 'ERR_UNKNOWN';
    }
  }

  @override
  String toString() =>
      'ApiException(${type.name}, status: $statusCode, $debugMessage)';
}
