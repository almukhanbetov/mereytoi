/// Every real `Notification.Type` value the backend actually fires —
/// mirrors the `Notif*` constants in backend/internal/models/notification.go
/// exactly. `manager_comment_added` is declared there but the handler that
/// would fire it (manager_chat_handler.go) never calls `createNotification`
/// at all — a new manager reply is discovered by polling the open chat, not
/// via the notification center — so there is deliberately no Flutter
/// constant/mapping for it here (never hardcode a type the backend doesn't
/// actually send).
library;

const notifInvitationAccepted = 'invitation_accepted';
const notifCandidateAdded = 'candidate_added';
const notifVoteAdded = 'vote_added';
const notifVoteChanged = 'vote_changed';
const notifCommentAdded = 'comment_added';
const notifBudgetUpdated = 'budget_updated';
const notifTaskCreated = 'task_created';
const notifTaskUpdated = 'task_updated';
const notifTaskCompleted = 'task_completed';
const notifMemberJoined = 'member_joined';
const notifMemberRoleChanged = 'member_role_changed';

const notifRequestSubmitted = 'request_submitted';
const notifRequestResubmitted = 'request_resubmitted';
const notifRequestInReview = 'request_in_review';
const notifRequestChangesRequested = 'request_changes_requested';
const notifRequestApproved = 'request_approved';
const notifRequestRejected = 'request_rejected';
const notifRequestCancelled = 'request_cancelled';

const notifWorkspaceCreated = 'workspace_created';

/// Deep-link target for a notification — an event workspace opened to a
/// specific tab, resolved from the real `entity_type` the backend actually
/// sets per notification (see notification_helpers.go's call sites):
/// "candidate" → Услуги, "discussion"/"comment_added" without a candidate →
/// Обсуждение, "task" → Задачи, "member" → Участники, "request" (or any
/// request_* type) → Обзор, "event"/budget_updated/workspace_created →
/// Обзор. Anything unrecognized resolves to `null` — the notification is
/// still shown and can be marked read, it just doesn't navigate anywhere.
typedef NotificationTarget = ({int eventId, int tabIndex});

/// Tab indices, matching `EventWorkspaceScreen`'s own tab order exactly:
/// Обзор=0, Услуги=1, Бюджет=2, Обсуждение=3, Задачи=4, Участники=5.
const _tabOverview = 0;
const _tabCandidates = 1;
const _tabDiscussion = 3;
const _tabTasks = 4;
const _tabMembers = 5;

NotificationTarget? resolveNotificationTarget({
  required String type,
  String? entityType,
  int? eventId,
}) {
  if (eventId == null) return null;

  switch (entityType) {
    case 'candidate':
      return (eventId: eventId, tabIndex: _tabCandidates);
    case 'discussion':
      return (eventId: eventId, tabIndex: _tabDiscussion);
    case 'task':
      return (eventId: eventId, tabIndex: _tabTasks);
    case 'member':
      return (eventId: eventId, tabIndex: _tabMembers);
    case 'request':
      return (eventId: eventId, tabIndex: _tabOverview);
    case 'event':
      return (eventId: eventId, tabIndex: _tabOverview);
  }

  // entity_type is absent for a handful of types — fall back to the
  // notification's own `type` where that's still unambiguous.
  if (type.startsWith('request_')) {
    return (eventId: eventId, tabIndex: _tabOverview);
  }
  if (type == notifBudgetUpdated || type == notifWorkspaceCreated) {
    return (eventId: eventId, tabIndex: _tabOverview);
  }
  if (type == notifCommentAdded) {
    return (eventId: eventId, tabIndex: _tabDiscussion);
  }

  return null;
}
