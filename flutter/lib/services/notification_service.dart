import '../core/network/api_client.dart';
import '../models/app_notification.dart';

/// Wraps the real `/api/notifications*` endpoints (auth-only, always
/// scoped to the caller — there is no "list someone else's" mode).
class NotificationService {
  NotificationService(this._client);

  final ApiClient _client;

  /// `GET /api/notifications?unread=true&page=1&limit=20`. Returns
  /// `(notifications, total)` — `total` is the real server-side count for
  /// this filter, not just `notifications.length` (useful for "load more").
  Future<(List<AppNotification>, int)> list({
    bool unreadOnly = false,
    int page = 1,
    int limit = 20,
  }) async {
    final json = await _client.getJson(
      '/api/notifications',
      query: {if (unreadOnly) 'unread': 'true', 'page': page, 'limit': limit},
    );
    final raw = json['notifications'] as List? ?? const [];
    final notifications = raw
        .map(
          (e) => AppNotification.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
    final total = json['total'] as int? ?? notifications.length;
    return (notifications, total);
  }

  Future<int> unreadCount() async {
    final json = await _client.getJson('/api/notifications/unread-count');
    return json['count'] as int? ?? 0;
  }

  Future<AppNotification> markRead(int id) async {
    final json = await _client.postJson('/api/notifications/$id/read', {});
    return AppNotification.fromJson(
      Map<String, dynamic>.from(json['notification'] as Map),
    );
  }

  Future<void> markAllRead() {
    return _client.postJson('/api/notifications/read-all', {});
  }
}
