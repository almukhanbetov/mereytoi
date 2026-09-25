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

/// Chat notifications (Этап 11G / 12A) — addressed by conversation, not by
/// event: `entity_type` is `provider_conversation`/`manager_conversation`
/// and `entity_id` the conversation id; `event_id` is never set.
/// `manager_chat_user_message` only ever reaches admins (a customer wrote
/// to the managers) — its thread lives in the web admin inbox, so it's
/// rendered but has no in-app destination.
const notifProviderMessageReceived = 'provider_message_received';
const notifManagerMessageReceived = 'manager_message_received';
const notifManagerChatUserMessage = 'manager_chat_user_message';

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

/// Deep-link target for a chat notification — resolved separately from
/// [resolveNotificationTarget], since these open a conversation screen
/// rather than an event workspace tab.
sealed class ChatNotificationTarget {
  const ChatNotificationTarget({required this.conversationId});

  final int conversationId;
}

/// Opens `ManagerChatScreen` on exactly this thread; [eventId]/[listingId]
/// are only the display context (the thread itself is fetched by id).
class ManagerChatNotificationTarget extends ChatNotificationTarget {
  const ManagerChatNotificationTarget({
    required super.conversationId,
    this.eventId,
    this.listingId,
  });

  final int? eventId;
  final int? listingId;
}

/// Opens `ProviderChatScreen` by [conversationId] — the direct `GET
/// /api/provider-chat/:id` path, which works for whichever side (customer
/// or provider) the recipient is on. [peerName] is the sender as the
/// recipient knows them (the backend's `sender_name`).
class ProviderChatNotificationTarget extends ChatNotificationTarget {
  const ProviderChatNotificationTarget({
    required super.conversationId,
    required this.providerId,
    required this.peerName,
    this.listingId,
  });

  final int providerId;
  final String peerName;
  final int? listingId;
}

int? _payloadInt(Map<String, dynamic> payload, String key) {
  final v = payload[key];
  return v is num ? v.toInt() : null;
}

/// [fallbackPeerName] covers notifications created before the backend
/// started sending `sender_name` (Этап 12A) — the caller passes the
/// notification's own actor name.
ChatNotificationTarget? resolveChatNotificationTarget({
  required String type,
  String? entityType,
  int? entityId,
  Map<String, dynamic> payload = const {},
  String? fallbackPeerName,
}) {
  if (entityId == null) return null;

  if (type == notifManagerMessageReceived &&
      entityType == 'manager_conversation') {
    return ManagerChatNotificationTarget(
      conversationId: entityId,
      eventId: _payloadInt(payload, 'event_id'),
      listingId: _payloadInt(payload, 'listing_id'),
    );
  }

  if (type == notifProviderMessageReceived &&
      entityType == 'provider_conversation') {
    final senderName = payload['sender_name'];
    return ProviderChatNotificationTarget(
      conversationId: entityId,
      // Older rows have no provider_id; the screen never needs it when a
      // conversationId is known (it's only used by the customer-side
      // start path), so 0 is a safe placeholder there.
      providerId: _payloadInt(payload, 'provider_id') ?? 0,
      listingId: _payloadInt(payload, 'listing_id'),
      peerName: senderName is String && senderName.isNotEmpty
          ? senderName
          : (fallbackPeerName ?? '—'),
    );
  }

  return null;
}
