import '../core/network/api_client.dart';
import '../models/event.dart';
import '../models/event_activity.dart';
import '../models/event_candidate.dart';
import '../models/event_comment.dart';
import '../models/event_member.dart';
import '../models/event_request.dart';
import '../models/event_summary.dart';
import '../models/event_task.dart';
import '../models/event_vote.dart';

/// Wraps every real `/api/events*` + `/api/invitations*` endpoint this app
/// uses for "Мой той" (Stage 4) — mirrors frontend/src/lib/eventsApi.js
/// route-for-route, no invented endpoint. Uses the same [ApiClient]/Bearer
/// auth every other Service already goes through; every method here
/// requires a session (every route is behind `middleware.RequireAuth`), so
/// callers must check auth state before calling (see AuthState in
/// state/auth_provider.dart) rather than relying on a guaranteed 401.
class EventService {
  EventService(this._client);

  final ApiClient _client;

  // ---- Events ----

  Future<List<Event>> list() async {
    final json = await _client.getJson('/api/events');
    final raw = json['events'] as List? ?? const [];
    return raw
        .map((e) => Event.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<Event> create({
    required String title,
    required String type,
    DateTime? eventDate,
    required String city,
    required int guests,
    required int budgetTotal,
    required String comment,
  }) async {
    final json = await _client.postJson(
      '/api/events',
      Event.toInputJson(
        title: title,
        type: type,
        eventDate: eventDate,
        city: city,
        guests: guests,
        budgetTotal: budgetTotal,
        comment: comment,
      ),
    );
    return Event.fromJson(Map<String, dynamic>.from(json['event'] as Map));
  }

  /// `GET /api/events/:id` — `my_role` arrives as a sibling of `"event"`,
  /// not nested inside it; folded onto the event map before parsing so
  /// `Event.fromJson` only ever has to handle one shape (see [Event]'s own
  /// doc comment).
  Future<Event> get(int eventId) async {
    final json = await _client.getJson('/api/events/$eventId');
    final eventJson = Map<String, dynamic>.from(json['event'] as Map);
    eventJson['my_role'] = json['my_role'];
    return Event.fromJson(eventJson);
  }

  Future<Event> update({
    required int eventId,
    required String title,
    required String type,
    DateTime? eventDate,
    required String city,
    required int guests,
    required int budgetTotal,
    required String comment,
  }) async {
    final json = await _client.putJson(
      '/api/events/$eventId',
      Event.toInputJson(
        title: title,
        type: type,
        eventDate: eventDate,
        city: city,
        guests: guests,
        budgetTotal: budgetTotal,
        comment: comment,
      ),
    );
    return Event.fromJson(Map<String, dynamic>.from(json['event'] as Map));
  }

  Future<void> delete(int eventId) =>
      _client.deleteJson('/api/events/$eventId');

  Future<EventSummary> summary(int eventId) async {
    final json = await _client.getJson('/api/events/$eventId/summary');
    return EventSummary.fromJson(json);
  }

  // ---- Candidates ----

  Future<List<EventCandidate>> candidates(int eventId) async {
    final json = await _client.getJson('/api/events/$eventId/candidates');
    final raw = json['candidates'] as List? ?? const [];
    return raw
        .map(
          (e) => EventCandidate.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  }

  /// Returns `(candidate, alreadyAdded)` — `alreadyAdded` mirrors the
  /// backend's own idempotent-on-variant-identity behavior (re-adding the
  /// exact same listing/hall/menu combination returns the existing row
  /// instead of creating a duplicate), so the caller can show "уже
  /// добавлено" instead of a generic success toast.
  Future<(EventCandidate, bool)> addCandidate({
    required int eventId,
    required int listingId,
    int? hallId,
    int? menuId,
    int? guests,
    int? estimatedTotal,
  }) async {
    final json = await _client.postJson(
      '/api/events/$eventId/candidates',
      EventCandidate.toAddCandidateJson(
        listingId: listingId,
        hallId: hallId,
        menuId: menuId,
        guests: guests,
        estimatedTotal: estimatedTotal,
      ),
    );
    final candidate = EventCandidate.fromJson(
      Map<String, dynamic>.from(json['candidate'] as Map),
    );
    return (candidate, json['already_added'] as bool? ?? false);
  }

  Future<EventCandidate> updateCandidateStatus({
    required int eventId,
    required int candidateId,
    required String status,
  }) async {
    final json = await _client.putJson(
      '/api/events/$eventId/candidates/$candidateId',
      {'status': status},
    );
    return EventCandidate.fromJson(
      Map<String, dynamic>.from(json['candidate'] as Map),
    );
  }

  Future<void> removeCandidate({
    required int eventId,
    required int candidateId,
  }) {
    return _client.deleteJson('/api/events/$eventId/candidates/$candidateId');
  }

  Future<EventVote> vote({
    required int eventId,
    required int candidateId,
    required String value,
  }) async {
    final json = await _client.postJson(
      '/api/events/$eventId/candidates/$candidateId/vote',
      {'value': value},
    );
    return EventVote.fromJson(Map<String, dynamic>.from(json['vote'] as Map));
  }

  // ---- Comments ----

  /// `candidateId == null` → the event-wide "Обсуждение" tab; set → that
  /// one candidate's own thread — same as `?candidate_id=` on the backend.
  Future<List<EventComment>> comments({
    required int eventId,
    int? candidateId,
  }) async {
    final json = await _client.getJson(
      '/api/events/$eventId/comments',
      query: candidateId == null ? null : {'candidate_id': candidateId},
    );
    final raw = json['comments'] as List? ?? const [];
    return raw
        .map((e) => EventComment.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<EventComment> addComment({
    required int eventId,
    required String body,
    int? candidateId,
  }) async {
    final json = await _client.postJson('/api/events/$eventId/comments', {
      'body': body,
      'candidate_id': candidateId,
    });
    return EventComment.fromJson(
      Map<String, dynamic>.from(json['comment'] as Map),
    );
  }

  Future<void> deleteComment({required int eventId, required int commentId}) {
    return _client.deleteJson('/api/events/$eventId/comments/$commentId');
  }

  // ---- Activity ----

  Future<List<EventActivity>> activity(int eventId) async {
    final json = await _client.getJson('/api/events/$eventId/activity');
    final raw = json['activity'] as List? ?? const [];
    return raw
        .map((e) => EventActivity.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  // ---- Tasks ----

  Future<List<EventTask>> tasks(int eventId) async {
    final json = await _client.getJson('/api/events/$eventId/tasks');
    final raw = json['tasks'] as List? ?? const [];
    return raw
        .map((e) => EventTask.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<EventTask> createTask({
    required int eventId,
    required String title,
    int? assigneeId,
    DateTime? dueDate,
  }) async {
    final json = await _client.postJson(
      '/api/events/$eventId/tasks',
      EventTask.toCreateJson(
        title: title,
        assigneeId: assigneeId,
        dueDate: dueDate,
      ),
    );
    return EventTask.fromJson(Map<String, dynamic>.from(json['task'] as Map));
  }

  /// Any member (including viewers) may flip `status` alone — the backend
  /// only requires editor+ when title/assignee/due date also change (see
  /// `EventTaskHandler.Update`'s `onlyStatusChange` check) — so this sends
  /// *only* `status`, never the other fields, to stay on the viewer-allowed
  /// path for the common "mark done" action.
  Future<EventTask> updateTaskStatus({
    required int eventId,
    required int taskId,
    required String status,
  }) async {
    final json = await _client.putJson('/api/events/$eventId/tasks/$taskId', {
      'status': status,
    });
    return EventTask.fromJson(Map<String, dynamic>.from(json['task'] as Map));
  }

  Future<EventTask> updateTask({
    required int eventId,
    required int taskId,
    required String title,
    int? assigneeId,
    DateTime? dueDate,
  }) async {
    final json = await _client.putJson(
      '/api/events/$eventId/tasks/$taskId',
      EventTask.toCreateJson(
        title: title,
        assigneeId: assigneeId,
        dueDate: dueDate,
      ),
    );
    return EventTask.fromJson(Map<String, dynamic>.from(json['task'] as Map));
  }

  Future<void> deleteTask({required int eventId, required int taskId}) {
    return _client.deleteJson('/api/events/$eventId/tasks/$taskId');
  }

  // ---- Members / invitations ----

  Future<List<EventMember>> members(int eventId) async {
    final json = await _client.getJson('/api/events/$eventId/members');
    final raw = json['members'] as List? ?? const [];
    return raw
        .map((e) => EventMember.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> changeMemberRole({
    required int eventId,
    required int userId,
    required String role,
  }) {
    return _client.putJson('/api/events/$eventId/members/$userId', {
      'role': role,
    });
  }

  Future<void> removeMember({required int eventId, required int userId}) {
    return _client.deleteJson('/api/events/$eventId/members/$userId');
  }

  Future<List<EventInvitation>> listInvitations(int eventId) async {
    final json = await _client.getJson('/api/events/$eventId/invitations');
    final raw = json['invitations'] as List? ?? const [];
    return raw
        .map(
          (e) => EventInvitation.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  }

  /// `email` optional — the join link works the same either way; when
  /// given, the backend also emails it there.
  Future<EventInvitation> createInvitation({
    required int eventId,
    required String role,
    String? email,
  }) async {
    final body = <String, dynamic>{'role': role};
    if (email != null && email.isNotEmpty) body['email'] = email;
    final json = await _client.postJson(
      '/api/events/$eventId/invitations',
      body,
    );
    return EventInvitation.fromJson(
      Map<String, dynamic>.from(json['invitation'] as Map),
    );
  }

  Future<void> revokeInvitation({
    required int eventId,
    required int invitationId,
  }) {
    return _client.deleteJson('/api/events/$eventId/invitations/$invitationId');
  }

  // ---- Request (submit to MEREYTOI) ----

  Future<(EventRequest, List<EventRequestRevision>)> getRequest(
    int eventId,
  ) async {
    final json = await _client.getJson('/api/events/$eventId/request');
    final request = EventRequest.fromJson(
      Map<String, dynamic>.from(json['request'] as Map),
    );
    final rawRevisions = json['revisions'] as List? ?? const [];
    final revisions = rawRevisions
        .map(
          (e) => EventRequestRevision.fromJson(
            Map<String, dynamic>.from(e as Map),
          ),
        )
        .toList();
    return (request, revisions);
  }

  Future<EventRequest> updateRequest({
    required int eventId,
    required String organizerComment,
  }) async {
    final json = await _client.putJson('/api/events/$eventId/request', {
      'organizer_comment': organizerComment,
    });
    return EventRequest.fromJson(
      Map<String, dynamic>.from(json['request'] as Map),
    );
  }

  /// Returns `(request, alreadySubmitted)` — idempotent on the backend:
  /// calling this again while already submitted/decided just returns the
  /// current state (200, `already_submitted: true`), never a 409.
  Future<(EventRequest, bool)> submitRequest(int eventId) async {
    final json = await _client.postJson(
      '/api/events/$eventId/request/submit',
      {},
    );
    final request = EventRequest.fromJson(
      Map<String, dynamic>.from(json['request'] as Map),
    );
    return (request, json['already_submitted'] as bool? ?? false);
  }

  Future<EventRequest> cancelRequest(int eventId) async {
    final json = await _client.postJson(
      '/api/events/$eventId/request/cancel',
      {},
    );
    return EventRequest.fromJson(
      Map<String, dynamic>.from(json['request'] as Map),
    );
  }

  // ---- Invitation accept/preview (outside /events/:id — see routes.go) ----

  Future<Map<String, dynamic>> previewInvitation(String token) {
    return _client.getJson('/api/invitations/$token');
  }

  /// Returns `(eventId, role, alreadyMember)`.
  Future<(int, String, bool)> acceptInvitation(String token) async {
    final json = await _client.postJson('/api/invitations/$token/accept', {});
    return (
      json['event_id'] as int,
      json['role'] as String? ?? '',
      json['already_member'] as bool? ?? false,
    );
  }
}
