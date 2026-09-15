import 'user.dart';

/// Mirrors backend/internal/models/event.go's `EventActivity` — an
/// append-only feed entry. `payload` is already decoded server-side
/// (`event_activity_handler.go`'s `List` unmarshals `Payload` into
/// `PayloadJSON` before responding), so this only ever reads the `payload`
/// key, never the raw string.
class EventActivity {
  const EventActivity({
    required this.id,
    required this.eventId,
    this.actorId,
    this.actor,
    required this.verb,
    this.payload = const {},
    required this.createdAt,
  });

  final int id;
  final int eventId;

  /// null = system-generated entry (no human actor).
  final int? actorId;
  final User? actor;
  final String verb;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  factory EventActivity.fromJson(Map<String, dynamic> json) {
    return EventActivity(
      id: json['id'] as int,
      eventId: json['event_id'] as int? ?? 0,
      actorId: json['actor_id'] as int?,
      actor: json['actor'] is Map
          ? User.fromJson(Map<String, dynamic>.from(json['actor'] as Map))
          : null,
      verb: json['verb'] as String? ?? '',
      payload: json['payload'] is Map
          ? Map<String, dynamic>.from(json['payload'] as Map)
          : const {},
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
