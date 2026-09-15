import 'event.dart';
import 'listing.dart';
import 'user.dart';

/// Mirrors backend/internal/models/manager_chat.go's `ManagerConversation`
/// — a real two-way thread with MEREYTOI's manager, authenticated-only.
/// Deliberately distinct from Event comments (the team's own internal
/// discussion, never seen by a manager) and from Notification
/// (one-directional, system-generated).
class ManagerConversation {
  const ManagerConversation({
    required this.id,
    required this.userId,
    this.user,
    this.eventId,
    this.event,
    this.listingId,
    this.listing,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int userId;
  final User? user;

  /// "What page were they on" context — both optional/independent: a
  /// conversation can be general (both null), about one service
  /// (listingId only), about one event (eventId only), or both.
  final int? eventId;
  final Event? event;
  final int? listingId;
  final Listing? listing;

  /// open | closed — closing is a manual admin action only.
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory ManagerConversation.fromJson(Map<String, dynamic> json) {
    return ManagerConversation(
      id: json['id'] as int,
      userId: json['user_id'] as int? ?? 0,
      user: json['user'] is Map
          ? User.fromJson(Map<String, dynamic>.from(json['user'] as Map))
          : null,
      eventId: json['event_id'] as int?,
      event: json['event'] is Map
          ? Event.fromJson(Map<String, dynamic>.from(json['event'] as Map))
          : null,
      listingId: json['listing_id'] as int?,
      listing: json['listing'] is Map
          ? Listing.fromJson(Map<String, dynamic>.from(json['listing'] as Map))
          : null,
      status: json['status'] as String? ?? 'open',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
