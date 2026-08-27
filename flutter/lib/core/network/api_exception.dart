/// Broad failure category — kept locale-free here (RU/KZ text lives in
/// core/utils/app_strings.dart) so a screen can show a bilingual message
/// instead of a raw Dio/HTTP exception or stack trace.
enum ApiErrorType { network, timeout, notFound, server, unknown }

class ApiException implements Exception {
  const ApiException(this.type, {this.statusCode, this.debugMessage});

  final ApiErrorType type;
  final int? statusCode;
  final String? debugMessage;

  @override
  String toString() => 'ApiException(${type.name}, status: $statusCode, $debugMessage)';
}
