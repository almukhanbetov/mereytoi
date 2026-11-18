import '../core/network/api_client.dart';
import '../models/user_report.dart';

/// Users' complaints — POST /api/reports, GET /api/reports/mine.
class ReportService {
  ReportService(this._client);

  final ApiClient _client;

  /// [targetType]: listing | provider | comment | user. [reason]: spam |
  /// fraud | abuse | inappropriate | rights | other.
  Future<void> create({
    required String targetType,
    required int targetId,
    required String reason,
    String details = '',
  }) => _client.postJson('/api/reports', {
    'target_type': targetType,
    'target_id': targetId,
    'reason': reason,
    'details': details,
  });

  Future<List<UserReport>> mine() async {
    final json = await _client.getJson('/api/reports/mine');
    final raw = json['reports'] as List? ?? const [];
    return raw
        .whereType<Map>()
        .map((e) => UserReport.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}
