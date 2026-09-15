/// Mirrors backend/internal/models/event.go's `Event` JSON shape exactly —
/// GET/POST/PUT /api/events(/:id).
///
/// `myRole` is never a field on the Go struct itself — it rides as a
/// sibling JSON key next to the event's own fields on two different
/// endpoints, in two different shapes: `GET /api/events` embeds it inline
/// on each list row (`eventWithRole` anonymously embeds `models.Event` +
/// `MyRole`, so Go's JSON marshaling flattens both onto the same object),
/// while `GET /api/events/:id` sends it as a true sibling of `"event"`
/// (`{"event": {...}, "my_role": "..."}`). `EventService` normalizes both
/// into the same flat map before this ever parses it, so `Event.fromJson`
/// only has to handle one shape: `my_role` alongside every other field.
class Event {
  const Event({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.type,
    this.eventDate,
    required this.city,
    required this.guests,
    required this.budgetTotal,
    required this.comment,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.myRole,
  });

  final int id;
  final int ownerId;
  final String title;
  final String type;
  final DateTime? eventDate;
  final String city;
  final int guests;
  final int budgetTotal;
  final String comment;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// The caller's own role on this event ("viewer"/"editor"/"owner") —
  /// null only if it genuinely wasn't sent (never expected in practice,
  /// every real response includes it).
  final String? myRole;

  factory Event.fromJson(Map<String, dynamic> json) {
    return Event(
      id: json['id'] as int,
      ownerId: json['owner_id'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      type: json['type'] as String? ?? 'other',
      eventDate: json['event_date'] != null
          ? DateTime.tryParse(json['event_date'] as String)
          : null,
      city: json['city'] as String? ?? '',
      guests: json['guests'] as int? ?? 0,
      budgetTotal: json['budget_total'] as int? ?? 0,
      comment: json['comment'] as String? ?? '',
      status: json['status'] as String? ?? 'planning',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      myRole: json['my_role'] as String?,
    );
  }

  /// `eventInput` on the backend (event_handler.go) — the same body shape
  /// for both `POST /api/events` (create) and `PUT /api/events/:id`
  /// (update). `eventDate` is the `"2006-01-02"` string the handler's own
  /// `parseEventDate` expects, not a full ISO timestamp.
  static Map<String, dynamic> toInputJson({
    required String title,
    required String type,
    DateTime? eventDate,
    required String city,
    required int guests,
    required int budgetTotal,
    required String comment,
  }) {
    return {
      'title': title,
      'type': type,
      'event_date': eventDate == null
          ? null
          : '${eventDate.year.toString().padLeft(4, '0')}-'
                '${eventDate.month.toString().padLeft(2, '0')}-'
                '${eventDate.day.toString().padLeft(2, '0')}',
      'city': city,
      'guests': guests,
      'budget_total': budgetTotal,
      'comment': comment,
    };
  }
}
