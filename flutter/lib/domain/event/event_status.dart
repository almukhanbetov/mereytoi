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
      return t(locale, ru: 'Свадьба', kz: 'Үйлену тойы', en: 'Wedding');
    case eventTypeToi:
      return t(locale, ru: 'Той', kz: 'Той', en: 'Toi');
    case eventTypeAnniversary:
      return t(locale, ru: 'Юбилей', kz: 'Мерейтой', en: 'Anniversary');
    case eventTypeCorporate:
      return t(
        locale,
        ru: 'Корпоратив',
        kz: 'Корпоратив',
        en: 'Corporate event',
      );
    default:
      return t(locale, ru: 'Другое', kz: 'Басқа', en: 'Other');
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

/// Mirrors eventHelpers.js's `roleLabel`.
String eventRoleLabel(AppLocale locale, String role) {
  switch (role) {
    case eventRoleOwner:
      return t(locale, ru: 'Организатор', kz: 'Ұйымдастырушы', en: 'Organizer');
    case eventRoleEditor:
      return t(locale, ru: 'Участник', kz: 'Қатысушы', en: 'Member');
    case eventRoleViewer:
      return t(locale, ru: 'Наблюдатель', kz: 'Бақылаушы', en: 'Observer');
    default:
      return role;
  }
}

/// Mirrors eventHelpers.js's `candidateStatusLabel`.
String candidateStatusLabel(AppLocale locale, String status) {
  switch (status) {
    case candidateShortlisted:
      return t(
        locale,
        ru: 'Обсуждается',
        kz: 'Талқылануда',
        en: 'In discussion',
      );
    case candidateSelected:
      return t(locale, ru: 'Выбран', kz: 'Таңдалды', en: 'Selected');
    case candidateRejected:
      return t(locale, ru: 'Отклонён', kz: 'Қабылданбады', en: 'Declined');
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
      return t(locale, ru: 'К выполнению', kz: 'Орындау керек', en: 'To do');
    case taskDoing:
      return t(locale, ru: 'В процессе', kz: 'Орындалуда', en: 'In progress');
    case taskDone:
      return t(locale, ru: 'Готово', kz: 'Дайын', en: 'Done');
    default:
      return status;
  }
}

/// EventRequest.Status label.
String requestStatusLabel(AppLocale locale, String status) {
  switch (status) {
    case requestDraft:
      return t(locale, ru: 'Черновик', kz: 'Жоба', en: 'Draft');
    case requestSubmitted:
      return t(locale, ru: 'Отправлена', kz: 'Жіберілді', en: 'Sent');
    case requestInReview:
      return t(
        locale,
        ru: 'На рассмотрении',
        kz: 'Қаралуда',
        en: 'Under review',
      );
    case requestChangesRequested:
      return t(
        locale,
        ru: 'Нужны правки',
        kz: 'Түзету қажет',
        en: 'Changes needed',
      );
    case requestApproved:
      return t(locale, ru: 'Подтверждена', kz: 'Расталды', en: 'Confirmed');
    case requestRejected:
      return t(locale, ru: 'Отклонена', kz: 'Қабылданбады', en: 'Rejected');
    case requestCancelled:
      return t(locale, ru: 'Отменена', kz: 'Болдырылмады', en: 'Cancelled');
    default:
      return status;
  }
}
