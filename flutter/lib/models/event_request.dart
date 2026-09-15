import 'user.dart';

/// Mirrors backend/internal/models/event_request.go's `EventRequest` — the
/// "send this to MEREYTOI" side of the workspace, one per event. Deliberately
/// separate from `Booking`: this models the richer draft/review workflow
/// (revision history, manager back-and-forth); the plain cart-checkout
/// Booking pipeline is untouched.
class EventRequest {
  const EventRequest({
    required this.id,
    required this.eventId,
    required this.createdById,
    required this.status,
    required this.organizerComment,
    required this.managerComment,
    this.bookingId,
    required this.latestRevision,
    this.submittedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int eventId;
  final int createdById;

  /// draft | submitted | in_review | changes_requested | approved |
  /// rejected | cancelled — see domain/event/event_status.dart.
  final String status;
  final String organizerComment;
  final String managerComment;
  final int? bookingId;
  final int latestRevision;
  final DateTime? submittedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory EventRequest.fromJson(Map<String, dynamic> json) {
    return EventRequest(
      id: json['id'] as int,
      eventId: json['event_id'] as int? ?? 0,
      createdById: json['created_by_id'] as int? ?? 0,
      status: json['status'] as String? ?? 'draft',
      organizerComment: json['organizer_comment'] as String? ?? '',
      managerComment: json['manager_comment'] as String? ?? '',
      bookingId: json['booking_id'] as int?,
      latestRevision: json['latest_revision'] as int? ?? 0,
      submittedAt: json['submitted_at'] != null
          ? DateTime.tryParse(json['submitted_at'] as String)
          : null,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// Mirrors `EventRequestRevision` — one frozen snapshot of a request at the
/// moment it was (re)submitted. `snapshot` is already decoded server-side
/// (`Get`/`AdminGet` unmarshal `SnapshotJSON` into `Snapshot` before
/// responding), so this only ever reads the `snapshot` key.
class EventRequestRevision {
  const EventRequestRevision({
    required this.id,
    required this.eventRequestId,
    required this.revisionNumber,
    required this.submittedById,
    this.submittedBy,
    this.snapshot = const {},
    required this.total,
    required this.submittedAt,
    required this.createdAt,
  });

  final int id;
  final int eventRequestId;
  final int revisionNumber;
  final int submittedById;
  final User? submittedBy;
  final Map<String, dynamic> snapshot;
  final int total;
  final DateTime submittedAt;
  final DateTime createdAt;

  factory EventRequestRevision.fromJson(Map<String, dynamic> json) {
    return EventRequestRevision(
      id: json['id'] as int,
      eventRequestId: json['event_request_id'] as int? ?? 0,
      revisionNumber: json['revision_number'] as int? ?? 0,
      submittedById: json['submitted_by_id'] as int? ?? 0,
      submittedBy: json['submitted_by'] is Map
          ? User.fromJson(
              Map<String, dynamic>.from(json['submitted_by'] as Map),
            )
          : null,
      snapshot: json['snapshot'] is Map
          ? Map<String, dynamic>.from(json['snapshot'] as Map)
          : const {},
      total: json['total'] as int? ?? 0,
      submittedAt:
          DateTime.tryParse(json['submitted_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
