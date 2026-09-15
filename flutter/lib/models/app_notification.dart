import 'user.dart';

/// Mirrors backend/internal/models/notification.go's `Notification` —
/// named `AppNotification` here (not `Notification`) since
/// `package:flutter/widgets.dart` already exports a `Notification` class.
///
/// Deliberately no title/message text on the row itself — the backend
/// stores structured refs (`type` + `payload` + actor/event/entity) and
/// expects the client to render localized copy from `type` at read time
/// (same approach as `EventActivity`), so a RU→KZ switch never shows a
/// stale-language history.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.userId,
    this.actorId,
    this.actor,
    this.eventId,
    required this.type,
    this.entityType,
    this.entityId,
    this.payload = const {},
    required this.isRead,
    this.readAt,
    required this.createdAt,
  });

  final int id;
  final int userId;

  /// null = system-generated (no human actor).
  final int? actorId;
  final User? actor;
  final int? eventId;

  /// One of the `notif*` constants in domain/notification/notification_type.dart.
  final String type;

  /// The deep-link target, e.g. entityType="candidate"/entityId=12 —
  /// structured refs rather than a stored URL, so a later route rename
  /// can't leave an old notification pointing at a dead link.
  final String? entityType;
  final int? entityId;

  final Map<String, dynamic> payload;
  final bool isRead;
  final DateTime? readAt;
  final DateTime createdAt;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as int,
      userId: json['user_id'] as int? ?? 0,
      actorId: json['actor_id'] as int?,
      actor: json['actor'] is Map
          ? User.fromJson(Map<String, dynamic>.from(json['actor'] as Map))
          : null,
      eventId: json['event_id'] as int?,
      type: json['type'] as String? ?? '',
      entityType: json['entity_type'] as String?,
      entityId: json['entity_id'] as int?,
      payload: json['payload'] is Map
          ? Map<String, dynamic>.from(json['payload'] as Map)
          : const {},
      isRead: json['is_read'] as bool? ?? false,
      readAt: json['read_at'] != null
          ? DateTime.tryParse(json['read_at'] as String)
          : null,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
