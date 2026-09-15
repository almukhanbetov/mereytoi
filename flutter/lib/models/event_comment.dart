import 'user.dart';

/// Mirrors backend/internal/models/event.go's `EventComment` — one row
/// covers both the event-wide "Обсуждение" tab (`candidateId == null`) and
/// a per-candidate thread (`candidateId` set). Deliberately a different
/// feature from Manager Chat — this is workspace-team discussion, not a
/// channel to MEREYTOI staff.
class EventComment {
  const EventComment({
    required this.id,
    required this.eventId,
    this.candidateId,
    required this.userId,
    this.user,
    required this.body,
    required this.createdAt,
  });

  final int id;
  final int eventId;
  final int? candidateId;
  final int userId;
  final User? user;
  final String body;
  final DateTime createdAt;

  factory EventComment.fromJson(Map<String, dynamic> json) {
    return EventComment(
      id: json['id'] as int,
      eventId: json['event_id'] as int? ?? 0,
      candidateId: json['candidate_id'] as int?,
      userId: json['user_id'] as int? ?? 0,
      user: json['user'] is Map
          ? User.fromJson(Map<String, dynamic>.from(json['user'] as Map))
          : null,
      body: json['body'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
