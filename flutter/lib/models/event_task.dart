import 'user.dart';

/// Mirrors backend/internal/models/event.go's `EventTask` — deliberately
/// flat (no sub-tasks/priority/labels), matching the brief's own "не
/// превращать в Jira".
class EventTask {
  const EventTask({
    required this.id,
    required this.eventId,
    required this.title,
    this.assigneeId,
    this.assignee,
    this.dueDate,
    required this.status,
    required this.createdById,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int eventId;
  final String title;
  final int? assigneeId;
  final User? assignee;
  final DateTime? dueDate;

  /// todo | doing | done — see domain/event/event_status.dart.
  final String status;
  final int createdById;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory EventTask.fromJson(Map<String, dynamic> json) {
    return EventTask(
      id: json['id'] as int,
      eventId: json['event_id'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      assigneeId: json['assignee_id'] as int?,
      assignee: json['assignee'] is Map
          ? User.fromJson(Map<String, dynamic>.from(json['assignee'] as Map))
          : null,
      dueDate: json['due_date'] != null
          ? DateTime.tryParse(json['due_date'] as String)
          : null,
      status: json['status'] as String? ?? 'todo',
      createdById: json['created_by_id'] as int? ?? 0,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// `taskInput` on Create; `updateTaskInput` on Update carries the same
  /// three fields plus `status` — callers that only want to flip status
  /// build that map by hand (see EventService.updateTaskStatus) so a
  /// status-only PUT never re-sends title/assignee/due date.
  static Map<String, dynamic> toCreateJson({
    required String title,
    int? assigneeId,
    DateTime? dueDate,
  }) {
    return {
      'title': title,
      'assignee_id': assigneeId,
      'due_date': dueDate == null ? null : _isoDate(dueDate),
    };
  }

  static String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
