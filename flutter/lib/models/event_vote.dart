import 'user.dart';

/// Mirrors backend/internal/models/event.go's `EventVote` — the response
/// shape of `POST /api/events/:id/candidates/:cid/vote`. The workspace's
/// own candidate list already carries each candidate's tally/`myVote`
/// (see `EventCandidate`), so this is mostly parsed just to confirm the
/// write succeeded, not re-derived into UI state on its own.
class EventVote {
  const EventVote({
    required this.id,
    required this.candidateId,
    required this.userId,
    this.user,
    required this.value,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int candidateId;
  final int userId;
  final User? user;

  /// up | maybe | down — see domain/event/event_status.dart.
  final String value;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory EventVote.fromJson(Map<String, dynamic> json) {
    return EventVote(
      id: json['id'] as int,
      candidateId: json['candidate_id'] as int? ?? 0,
      userId: json['user_id'] as int? ?? 0,
      user: json['user'] is Map
          ? User.fromJson(Map<String, dynamic>.from(json['user'] as Map))
          : null,
      value: json['value'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
