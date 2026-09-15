import 'listing.dart';
import 'listing_hall.dart';
import 'listing_menu.dart';

/// Mirrors backend/internal/models/event.go's `EventCandidate`, plus the
/// vote-tally/comment-count enrichment `candidateOut`
/// (event_candidate_handler.go's `List`) adds on top. `AddCandidate`/
/// `UpdateStatus` return the bare `EventCandidate` (no `votes`/`my_vote`/
/// `comment_count` keys at all) — every one of those fields defaults
/// safely (`{}`/null/0) so the same `fromJson` parses either response
/// shape without throwing.
class EventCandidate {
  const EventCandidate({
    required this.id,
    required this.eventId,
    required this.listingId,
    this.listing,
    this.hallId,
    this.hall,
    this.menuId,
    this.menu,
    this.hallName,
    this.menuName,
    this.menuPricePerGuest,
    this.guests,
    this.estimatedTotal,
    required this.status,
    required this.addedById,
    required this.createdAt,
    required this.updatedAt,
    this.votes = const {},
    this.myVote,
    this.commentCount = 0,
  });

  final int id;
  final int eventId;
  final int listingId;

  /// The live listing — GET .../candidates Preloads it as the actual
  /// display source (source-of-truth pre-booking, see EventCandidate's own
  /// Go doc comment); null only on the bare Add/UpdateStatus response,
  /// where the caller already has the listing from wherever this candidate
  /// was created.
  final Listing? listing;

  final int? hallId;
  final ListingHall? hall;
  final int? menuId;
  final ListingMenu? menu;

  /// Denormalized snapshot taken at add-time — a defensive fallback only;
  /// prefer `hall?.name(locale)`/`menu?.name(locale)` while they're
  /// present, same priority the backend's own List() Preload implies.
  final String? hallName;
  final String? menuName;
  final int? menuPricePerGuest;

  /// This candidate's own guest count — null means "not specified" (every
  /// non-restaurant candidate), never coerced to 0; a budget view falls
  /// back to the event's own `guests` for those, same as
  /// eventHelpers.js's `candidateEstimate`.
  final int? guests;

  /// The calculator's frozen final total (menu×guests + extras) at
  /// add-time — null for every non-restaurant candidate and every
  /// candidate added before this field existed. Never recomputed from a
  /// live menu/extras lookup once set.
  final int? estimatedTotal;

  /// shortlisted | selected | rejected — see domain/event/event_status.dart.
  final String status;
  final int addedById;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Vote tally by value ("up"/"maybe"/"down" → count) — `{}` on the bare
  /// Add/UpdateStatus response, real counts from List().
  final Map<String, int> votes;

  /// The caller's own vote on this candidate, if any — empty/null means
  /// "hasn't voted", never a 4th vote value.
  final String? myVote;
  final int commentCount;

  factory EventCandidate.fromJson(Map<String, dynamic> json) {
    return EventCandidate(
      id: json['id'] as int,
      eventId: json['event_id'] as int? ?? 0,
      listingId: json['listing_id'] as int? ?? 0,
      listing: json['listing'] is Map
          ? Listing.fromJson(Map<String, dynamic>.from(json['listing'] as Map))
          : null,
      hallId: json['hall_id'] as int?,
      hall: json['hall'] is Map
          ? ListingHall.fromJson(Map<String, dynamic>.from(json['hall'] as Map))
          : null,
      menuId: json['menu_id'] as int?,
      menu: json['menu'] is Map
          ? ListingMenu.fromJson(Map<String, dynamic>.from(json['menu'] as Map))
          : null,
      hallName: json['hall_name'] as String?,
      menuName: json['menu_name'] as String?,
      menuPricePerGuest: json['menu_price_per_guest'] as int?,
      guests: json['guests'] as int?,
      estimatedTotal: json['estimated_total'] as int?,
      status: json['status'] as String? ?? 'shortlisted',
      addedById: json['added_by_id'] as int? ?? 0,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      votes:
          (json['votes'] as Map?)?.map(
            (k, v) => MapEntry(k as String, v as int? ?? 0),
          ) ??
          const {},
      myVote: (json['my_vote'] as String?)?.isNotEmpty == true
          ? json['my_vote'] as String
          : null,
      commentCount: (json['comment_count'] as num?)?.toInt() ?? 0,
    );
  }

  /// `addCandidateInput` on the backend (event_candidate_handler.go) — the
  /// body `POST /api/events/:id/candidates` expects. `hallId`/`menuId`
  /// both null is the plain-service shape; a restaurant variant sets
  /// whichever of hall/menu/guests/estimatedTotal it actually has.
  static Map<String, dynamic> toAddCandidateJson({
    required int listingId,
    int? hallId,
    int? menuId,
    int? guests,
    int? estimatedTotal,
  }) {
    return {
      'listing_id': listingId,
      'hall_id': hallId,
      'menu_id': menuId,
      'guests': guests,
      'estimated_total': estimatedTotal,
    };
  }
}
