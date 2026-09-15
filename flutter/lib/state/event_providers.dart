import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/event.dart';
import '../models/event_activity.dart';
import '../models/event_candidate.dart';
import '../models/event_comment.dart';
import '../models/event_member.dart';
import '../models/event_request.dart';
import '../models/event_summary.dart';
import '../models/event_task.dart';
import 'providers.dart';

/// Every event the current user belongs to (any role) — the "Мой той" list
/// screen's own data source.
final eventsProvider = FutureProvider<List<Event>>((ref) {
  return ref.watch(eventServiceProvider).list();
});

final eventDetailProvider = FutureProvider.family<Event, int>((ref, eventId) {
  return ref.watch(eventServiceProvider).get(eventId);
});

final eventSummaryProvider = FutureProvider.family<EventSummary, int>((
  ref,
  eventId,
) {
  return ref.watch(eventServiceProvider).summary(eventId);
});

final eventCandidatesProvider =
    FutureProvider.family<List<EventCandidate>, int>((ref, eventId) {
      return ref.watch(eventServiceProvider).candidates(eventId);
    });

/// Keyed by `(eventId, candidateId)` — `candidateId == null` is the
/// event-wide "Обсуждение" tab, matching `EventService.comments`'s own
/// optional parameter.
typedef EventCommentsKey = (int eventId, int? candidateId);

final eventCommentsProvider =
    FutureProvider.family<List<EventComment>, EventCommentsKey>((ref, key) {
      return ref
          .watch(eventServiceProvider)
          .comments(eventId: key.$1, candidateId: key.$2);
    });

final eventTasksProvider = FutureProvider.family<List<EventTask>, int>((
  ref,
  eventId,
) {
  return ref.watch(eventServiceProvider).tasks(eventId);
});

final eventActivityProvider = FutureProvider.family<List<EventActivity>, int>((
  ref,
  eventId,
) {
  return ref.watch(eventServiceProvider).activity(eventId);
});

final eventMembersProvider = FutureProvider.family<List<EventMember>, int>((
  ref,
  eventId,
) {
  return ref.watch(eventServiceProvider).members(eventId);
});

/// Owner-only on the backend (`GET /api/events/:id/invitations`) — only
/// ever watched from the Участники tab when `event.myRole == 'owner'`.
final eventInvitationsProvider =
    FutureProvider.family<List<EventInvitation>, int>((ref, eventId) {
      return ref.watch(eventServiceProvider).listInvitations(eventId);
    });

/// `(request, revisions)` — see `EventService.getRequest`.
final eventRequestProvider =
    FutureProvider.family<(EventRequest, List<EventRequestRevision>), int>((
      ref,
      eventId,
    ) {
      return ref.watch(eventServiceProvider).getRequest(eventId);
    });
