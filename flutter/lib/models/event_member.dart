import 'user.dart';

/// Mirrors backend/internal/models/event.go's `EventMember`.
class EventMember {
  const EventMember({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.role,
    this.user,
    required this.joinedAt,
  });

  final int id;
  final int eventId;
  final int userId;

  /// viewer | editor | owner — see domain/event/event_status.dart.
  final String role;
  final User? user;
  final DateTime joinedAt;

  factory EventMember.fromJson(Map<String, dynamic> json) {
    return EventMember(
      id: json['id'] as int,
      eventId: json['event_id'] as int? ?? 0,
      userId: json['user_id'] as int? ?? 0,
      role: json['role'] as String? ?? 'viewer',
      user: json['user'] is Map
          ? User.fromJson(Map<String, dynamic>.from(json['user'] as Map))
          : null,
      joinedAt:
          DateTime.tryParse(json['joined_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// Mirrors backend/internal/models/event.go's `EventInvitation` — a
/// reusable (revocable, not single-use) join link, exactly the shape
/// `POST/GET /api/events/:id/invitations` returns.
class EventInvitation {
  const EventInvitation({
    required this.id,
    required this.eventId,
    required this.token,
    required this.role,
    required this.createdById,
    this.inviteeEmail,
    required this.revoked,
    this.usedById,
    this.usedAt,
    required this.createdAt,
  });

  final int id;
  final int eventId;
  final String token;
  final String role;
  final int createdById;
  final String? inviteeEmail;
  final bool revoked;
  final int? usedById;
  final DateTime? usedAt;
  final DateTime createdAt;

  bool get isUsed => usedById != null;

  factory EventInvitation.fromJson(Map<String, dynamic> json) {
    return EventInvitation(
      id: json['id'] as int,
      eventId: json['event_id'] as int? ?? 0,
      token: json['token'] as String? ?? '',
      role: json['role'] as String? ?? 'viewer',
      createdById: json['created_by_id'] as int? ?? 0,
      inviteeEmail: json['invitee_email'] as String?,
      revoked: json['revoked'] as bool? ?? false,
      usedById: json['used_by_id'] as int?,
      usedAt: json['used_at'] != null
          ? DateTime.tryParse(json['used_at'] as String)
          : null,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
