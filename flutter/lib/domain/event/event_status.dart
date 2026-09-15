import '../../state/locale_provider.dart';

// Plain string statuses/enums the backend itself treats as free-form
// strings (see backend/internal/models/event.go, event_request.go) — kept
// as constants here, never a Dart `enum`, so an unfamiliar value the
// backend adds later degrades to "just a string" instead of crashing a
// `switch`.

// Event.Type — models.allowedEventTypes in event_handler.go.
const eventTypeWedding = 'wedding';
const eventTypeToi = 'toi';
const eventTypeAnniversary = 'anniversary';
const eventTypeCorporate = 'corporate';
const eventTypeOther = 'other';

// Event.Status.
const eventStatusPlanning = 'planning';
const eventStatusSubmitted = 'submitted';

// EventCandidate.Status.
const candidateShortlisted = 'shortlisted';
const candidateSelected = 'selected';
const candidateRejected = 'rejected';

// EventVote.Value.
const voteUp = 'up';
const voteMaybe = 'maybe';
const voteDown = 'down';

// EventTask.Status.
const taskTodo = 'todo';
const taskDoing = 'doing';
const taskDone = 'done';

// EventMember/EventInvitation.Role — models.EventRole* in event.go.
const eventRoleViewer = 'viewer';
const eventRoleEditor = 'editor';
const eventRoleOwner = 'owner';

/// Mirrors models.RoleRank exactly — an unknown role ranks *below* viewer
/// (no access), never above.
int eventRoleRank(String role) {
  switch (role) {
    case eventRoleOwner:
      return 3;
    case eventRoleEditor:
      return 2;
    case eventRoleViewer:
      return 1;
    default:
      return 0;
  }
}

// EventRequest.Status — models.Request* in event_request.go.
const requestDraft = 'draft';
const requestSubmitted = 'submitted';
const requestInReview = 'in_review';
const requestChangesRequested = 'changes_requested';
const requestApproved = 'approved';
const requestRejected = 'rejected';
const requestCancelled = 'cancelled';

/// Mirrors models.RequestEditable exactly.
bool requestIsEditable(String status) =>
    status == requestDraft || status == requestChangesRequested;

/// Mirrors models.RequestCancel's own inline switch in event_request_handler.go's
/// `Cancel` — the statuses past which cancelling is refused (409).
bool requestIsCancellable(String status) =>
    status != requestApproved &&
    status != requestRejected &&
    status != requestCancelled;

/// Mirrors eventHelpers.js's `eventTypeLabel` exactly (RU/KZ text and the
/// "unknown → other" fallback).
String eventTypeLabel(AppLocale locale, String type) {
  switch (type) {
    case eventTypeWedding:
      return t(locale, ru: 'Свадьба', kz: 'Үйлену тойы');
    case eventTypeToi:
      return t(locale, ru: 'Той', kz: 'Той');
    case eventTypeAnniversary:
      return t(locale, ru: 'Юбилей', kz: 'Мерейтой');
    case eventTypeCorporate:
      return t(locale, ru: 'Корпоратив', kz: 'Корпоратив');
    default:
      return t(locale, ru: 'Другое', kz: 'Басқа');
  }
}

/// Mirrors eventHelpers.js's `eventTypeEmoji` exactly.
String eventTypeEmoji(String type) {
  switch (type) {
    case eventTypeWedding:
      return '💍';
    case eventTypeToi:
      return '🎉';
    case eventTypeAnniversary:
      return '🥂';
    case eventTypeCorporate:
      return '🏢';
    default:
      return '✨';
  }
}

/// Mirrors eventHelpers.js's `roleLabel` (ru/kz branches — `en` is unused
/// here, this app's locale toggle only ever produces ru/kz).
String eventRoleLabel(AppLocale locale, String role) {
  switch (role) {
    case eventRoleOwner:
      return t(locale, ru: 'Организатор', kz: 'Ұйымдастырушы');
    case eventRoleEditor:
      return t(locale, ru: 'Участник', kz: 'Қатысушы');
    case eventRoleViewer:
      return t(locale, ru: 'Наблюдатель', kz: 'Бақылаушы');
    default:
      return role;
  }
}

/// Mirrors eventHelpers.js's `candidateStatusLabel`.
String candidateStatusLabel(AppLocale locale, String status) {
  switch (status) {
    case candidateShortlisted:
      return t(locale, ru: 'Обсуждается', kz: 'Талқылануда');
    case candidateSelected:
      return t(locale, ru: 'Выбран', kz: 'Таңдалды');
    case candidateRejected:
      return t(locale, ru: 'Отклонён', kz: 'Қабылданбады');
    default:
      return status;
  }
}

/// EventTask.Status label — no equivalent web helper for this one (the
/// site renders tasks as a plain checkbox), spelled out the same way the
/// other status labels above are.
String taskStatusLabel(AppLocale locale, String status) {
  switch (status) {
    case taskTodo:
      return t(locale, ru: 'К выполнению', kz: 'Орындау керек');
    case taskDoing:
      return t(locale, ru: 'В процессе', kz: 'Орындалуда');
    case taskDone:
      return t(locale, ru: 'Готово', kz: 'Дайын');
    default:
      return status;
  }
}

/// EventRequest.Status label.
String requestStatusLabel(AppLocale locale, String status) {
  switch (status) {
    case requestDraft:
      return t(locale, ru: 'Черновик', kz: 'Жоба');
    case requestSubmitted:
      return t(locale, ru: 'Отправлена', kz: 'Жіберілді');
    case requestInReview:
      return t(locale, ru: 'На рассмотрении', kz: 'Қаралуда');
    case requestChangesRequested:
      return t(locale, ru: 'Нужны правки', kz: 'Түзету қажет');
    case requestApproved:
      return t(locale, ru: 'Подтверждена', kz: 'Расталды');
    case requestRejected:
      return t(locale, ru: 'Отклонена', kz: 'Қабылданбады');
    case requestCancelled:
      return t(locale, ru: 'Отменена', kz: 'Болдырылмады');
    default:
      return status;
  }
}
