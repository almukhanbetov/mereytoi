import '../core/network/api_client.dart';
import '../models/admin.dart';

/// The mobile admin panel's API — /api/admin/* (stages 1–2 on the server).
/// Every call needs an administrator's session; the server checks the role
/// in the database on each request.
class AdminService {
  AdminService(this._client);

  final ApiClient _client;

  static const perPage = 20;

  AdminPage<T> _page<T>(
    Map<String, dynamic> json,
    String key,
    T Function(Map<String, dynamic>) parse,
  ) {
    final raw = json[key] as List? ?? const [];
    return AdminPage(
      items: raw
          .whereType<Map>()
          .map((e) => parse(Map<String, dynamic>.from(e)))
          .toList(),
      total: (json['total'] as num?)?.toInt() ?? 0,
      page: (json['page'] as num?)?.toInt() ?? 1,
      perPage: (json['per_page'] as num?)?.toInt() ?? perPage,
    );
  }

  Future<AdminSummary> summary() async =>
      AdminSummary.fromJson(await _client.getJson('/api/admin/summary'));

  /// [provider]: true — only users with a provider profile. [blocked]: true
  /// — only blocks in force now.
  Future<AdminPage<AdminUser>> searchUsers({
    String query = '',
    bool? provider,
    bool? blocked,
    int page = 1,
  }) async {
    final json = await _client.getJson(
      '/api/admin/users',
      query: {
        if (query.trim().isNotEmpty) 'q': query.trim(),
        if (provider != null) 'provider': provider ? '1' : '0',
        if (blocked != null) 'blocked': blocked ? '1' : '0',
        'page': '$page',
        'per_page': '$perPage',
      },
    );
    return _page(json, 'users', AdminUser.fromJson);
  }

  Future<AdminUserDetail> user(int id) async =>
      AdminUserDetail.fromJson(await _client.getJson('/api/admin/users/$id'));

  Future<void> warn(int userId, String reason) =>
      _client.postJson('/api/admin/users/$userId/warn', {'reason': reason});

  /// [duration]: 1d | 7d | 30d | permanent.
  Future<void> block(int userId, String reason, String duration) =>
      _client.postJson('/api/admin/users/$userId/block', {
        'reason': reason,
        'duration': duration,
      });

  Future<void> unblock(int userId, String reason) =>
      _client.postJson('/api/admin/users/$userId/unblock', {'reason': reason});

  Future<void> hideListing(int listingId, String reason) => _client.postJson(
    '/api/admin/listings/$listingId/hide',
    {'reason': reason},
  );

  Future<void> restoreListing(int listingId, String reason) => _client.postJson(
    '/api/admin/listings/$listingId/restore',
    {'reason': reason},
  );

  /// [status]: open | new | in_review | resolved | rejected, or null for all.
  Future<AdminPage<AdminReport>> reports({
    String? status,
    bool mine = false,
    int page = 1,
  }) async {
    final json = await _client.getJson(
      '/api/admin/reports',
      query: {
        'status': ?status,
        if (mine) 'assignee': 'me',
        'page': '$page',
        'per_page': '$perPage',
      },
    );
    return _page(json, 'reports', AdminReport.fromJson);
  }

  Future<AdminReportDetail> report(int id) async => AdminReportDetail.fromJson(
    await _client.getJson('/api/admin/reports/$id'),
  );

  Future<void> takeReport(int id) =>
      _client.postJson('/api/admin/reports/$id/take', const {});

  /// [decision]: resolved | rejected.
  Future<void> decideReport(int id, String decision, String reason) =>
      _client.postJson('/api/admin/reports/$id/decide', {
        'decision': decision,
        'reason': reason,
      });

  Future<AdminPage<AdminAuditEvent>> auditEvents({
    String? targetType,
    int? targetId,
    int page = 1,
  }) async {
    final json = await _client.getJson(
      '/api/admin/audit-events',
      query: {
        'target_type': ?targetType,
        if (targetId != null) 'target_id': '$targetId',
        'page': '$page',
        'per_page': '$perPage',
      },
    );
    return _page(json, 'events', AdminAuditEvent.fromJson);
  }
}
