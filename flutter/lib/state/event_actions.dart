import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/event.dart';
import '../models/event_candidate.dart';
import '../models/event_member.dart';
import '../models/event_request.dart';
import '../models/event_task.dart';
import 'event_providers.dart';
import 'providers.dart';

/// Every Event Workspace mutation in one place — each method calls the
/// matching `EventService` write, then invalidates exactly the providers
/// that read stale data as a result, so every screen watching them
/// refetches automatically. Deliberately plain `async` methods (not a
/// `StateNotifier<AsyncValue<T>>`) — Stage 4 has too many independent
/// mutations (event/candidate/vote/comment/task/member/invitation/request)
/// for one shared loading/error slot to mean anything; screens keep their
/// own local submitting/error state the same way `CartScreen`'s form
/// already does around `BookingSubmitNotifier`, catching whatever this
/// throws (an `ApiException`, same as every other Service) and rendering
/// it via the existing `apiErrorMessage`.
class EventActions {
  EventActions(this._ref);

  final Ref _ref;

  // ---- Event ----

  Future<Event> createEvent({
    required String title,
    required String type,
    DateTime? eventDate,
    required String city,
    required int guests,
    required int budgetTotal,
    required String comment,
  }) async {
    final event = await _ref
        .read(eventServiceProvider)
        .create(
          title: title,
          type: type,
          eventDate: eventDate,
          city: city,
          guests: guests,
          budgetTotal: budgetTotal,
          comment: comment,
        );
    _ref.invalidate(eventsProvider);
    return event;
  }

  Future<Event> updateEvent({
    required int eventId,
    required String title,
    required String type,
    DateTime? eventDate,
    required String city,
    required int guests,
    required int budgetTotal,
    required String comment,
  }) async {
    final event = await _ref
        .read(eventServiceProvider)
        .update(
          eventId: eventId,
          title: title,
          type: type,
          eventDate: eventDate,
          city: city,
          guests: guests,
          budgetTotal: budgetTotal,
          comment: comment,
        );
    _ref.invalidate(eventDetailProvider(eventId));
    _ref.invalidate(eventsProvider);
    return event;
  }

  Future<void> deleteEvent(int eventId) async {
    await _ref.read(eventServiceProvider).delete(eventId);
    _ref.invalidate(eventsProvider);
  }

  // ---- Candidates ----

  Future<(EventCandidate, bool)> addCandidate({
    required int eventId,
    required int listingId,
    int? hallId,
    int? menuId,
    int? guests,
    int? estimatedTotal,
  }) async {
    final result = await _ref
        .read(eventServiceProvider)
        .addCandidate(
          eventId: eventId,
          listingId: listingId,
          hallId: hallId,
          menuId: menuId,
          guests: guests,
          estimatedTotal: estimatedTotal,
        );
    _ref.invalidate(eventCandidatesProvider(eventId));
    _ref.invalidate(eventSummaryProvider(eventId));
    return result;
  }

  Future<void> updateCandidateStatus({
    required int eventId,
    required int candidateId,
    required String status,
  }) async {
    await _ref
        .read(eventServiceProvider)
        .updateCandidateStatus(
          eventId: eventId,
          candidateId: candidateId,
          status: status,
        );
    _ref.invalidate(eventCandidatesProvider(eventId));
    _ref.invalidate(eventSummaryProvider(eventId));
  }

  Future<void> removeCandidate({
    required int eventId,
    required int candidateId,
  }) async {
    await _ref
        .read(eventServiceProvider)
        .removeCandidate(eventId: eventId, candidateId: candidateId);
    _ref.invalidate(eventCandidatesProvider(eventId));
    _ref.invalidate(eventSummaryProvider(eventId));
  }

  Future<void> vote({
    required int eventId,
    required int candidateId,
    required String value,
  }) async {
    await _ref
        .read(eventServiceProvider)
        .vote(eventId: eventId, candidateId: candidateId, value: value);
    _ref.invalidate(eventCandidatesProvider(eventId));
  }

  // ---- Comments ----

  Future<void> addComment({
    required int eventId,
    required String body,
    int? candidateId,
  }) async {
    await _ref
        .read(eventServiceProvider)
        .addComment(eventId: eventId, body: body, candidateId: candidateId);
    _ref.invalidate(eventCommentsProvider((eventId, candidateId)));
    if (candidateId != null) {
      // comment_count on the candidate card is stale otherwise.
      _ref.invalidate(eventCandidatesProvider(eventId));
    }
  }

  Future<void> deleteComment({
    required int eventId,
    required int commentId,
    int? candidateId,
  }) async {
    await _ref
        .read(eventServiceProvider)
        .deleteComment(eventId: eventId, commentId: commentId);
    _ref.invalidate(eventCommentsProvider((eventId, candidateId)));
    if (candidateId != null) {
      _ref.invalidate(eventCandidatesProvider(eventId));
    }
  }

  // ---- Tasks ----

  Future<EventTask> createTask({
    required int eventId,
    required String title,
    int? assigneeId,
    DateTime? dueDate,
  }) async {
    final task = await _ref
        .read(eventServiceProvider)
        .createTask(
          eventId: eventId,
          title: title,
          assigneeId: assigneeId,
          dueDate: dueDate,
        );
    _ref.invalidate(eventTasksProvider(eventId));
    return task;
  }

  Future<void> updateTaskStatus({
    required int eventId,
    required int taskId,
    required String status,
  }) async {
    await _ref
        .read(eventServiceProvider)
        .updateTaskStatus(eventId: eventId, taskId: taskId, status: status);
    _ref.invalidate(eventTasksProvider(eventId));
  }

  Future<void> deleteTask({required int eventId, required int taskId}) async {
    await _ref
        .read(eventServiceProvider)
        .deleteTask(eventId: eventId, taskId: taskId);
    _ref.invalidate(eventTasksProvider(eventId));
  }

  // ---- Members / invitations ----

  Future<void> changeMemberRole({
    required int eventId,
    required int userId,
    required String role,
  }) async {
    await _ref
        .read(eventServiceProvider)
        .changeMemberRole(eventId: eventId, userId: userId, role: role);
    _ref.invalidate(eventMembersProvider(eventId));
  }

  Future<void> removeMember({required int eventId, required int userId}) async {
    await _ref
        .read(eventServiceProvider)
        .removeMember(eventId: eventId, userId: userId);
    _ref.invalidate(eventMembersProvider(eventId));
  }

  Future<EventInvitation> createInvitation({
    required int eventId,
    required String role,
    String? email,
  }) async {
    final invitation = await _ref
        .read(eventServiceProvider)
        .createInvitation(eventId: eventId, role: role, email: email);
    _ref.invalidate(eventInvitationsProvider(eventId));
    return invitation;
  }

  Future<void> revokeInvitation({
    required int eventId,
    required int invitationId,
  }) async {
    await _ref
        .read(eventServiceProvider)
        .revokeInvitation(eventId: eventId, invitationId: invitationId);
    _ref.invalidate(eventInvitationsProvider(eventId));
  }

  // ---- Request ----

  Future<void> updateRequestComment({
    required int eventId,
    required String organizerComment,
  }) async {
    await _ref
        .read(eventServiceProvider)
        .updateRequest(eventId: eventId, organizerComment: organizerComment);
    _ref.invalidate(eventRequestProvider(eventId));
  }

  Future<(EventRequest, bool)> submitRequest(int eventId) async {
    final result = await _ref.read(eventServiceProvider).submitRequest(eventId);
    _ref.invalidate(eventRequestProvider(eventId));
    _ref.invalidate(eventDetailProvider(eventId));
    _ref.invalidate(eventsProvider);
    return result;
  }

  Future<EventRequest> cancelRequest(int eventId) async {
    final request = await _ref
        .read(eventServiceProvider)
        .cancelRequest(eventId);
    _ref.invalidate(eventRequestProvider(eventId));
    _ref.invalidate(eventDetailProvider(eventId));
    _ref.invalidate(eventsProvider);
    return request;
  }
}

final eventActionsProvider = Provider<EventActions>((ref) => EventActions(ref));
