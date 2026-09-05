import { roleLabel } from '@/lib/eventHelpers';
import { formatPrice } from '@/lib/format';

// Deliberately no title/message text is stored on the notification row
// (see backend/internal/models/notification.go) — it's rendered here, from
// `type` + `payload`, so switching RU/KZ/EN always shows the current
// language even for old notifications. Mirrors the same idea as
// lib/eventHelpers.js's activityLine() for the event activity feed.

const TITLES = {
  invitation_accepted: { ru: 'Приглашение принято', kz: 'Шақыру қабылданды', en: 'Invitation accepted' },
  candidate_added: { ru: 'Новая услуга', kz: 'Жаңа қызмет', en: 'New service' },
  vote_added: { ru: 'Новый голос', kz: 'Жаңа дауыс', en: 'New vote' },
  vote_changed: { ru: 'Голос изменён', kz: 'Дауыс өзгертілді', en: 'Vote changed' },
  comment_added: { ru: 'Новый комментарий', kz: 'Жаңа пікір', en: 'New comment' },
  budget_updated: { ru: 'Бюджет обновлён', kz: 'Бюджет жаңартылды', en: 'Budget updated' },
  task_created: { ru: 'Новая задача', kz: 'Жаңа тапсырма', en: 'New task' },
  task_updated: { ru: 'Задача изменена', kz: 'Тапсырма өзгертілді', en: 'Task updated' },
  task_completed: { ru: 'Задача выполнена', kz: 'Тапсырма орындалды', en: 'Task completed' },
  member_joined: { ru: 'Новый участник', kz: 'Жаңа қатысушы', en: 'New member' },
  member_role_changed: { ru: 'Роль изменена', kz: 'Рөл өзгертілді', en: 'Role changed' },

  // 10B — request lifecycle + manager decisions.
  request_submitted: { ru: 'Новая заявка', kz: 'Жаңа өтінім', en: 'New request' },
  request_resubmitted: { ru: 'Заявка отправлена повторно', kz: 'Өтінім қайта жіберілді', en: 'Request resubmitted' },
  request_in_review: { ru: 'Заявка принята в работу', kz: 'Өтінім қарауға алынды', en: 'Request in review' },
  request_changes_requested: { ru: 'Требуется действие', kz: 'Әрекет қажет', en: 'Action required' },
  request_approved: { ru: 'Заявка подтверждена', kz: 'Өтінім расталды', en: 'Request approved' },
  request_rejected: { ru: 'Заявка отклонена', kz: 'Өтінім қабылданбады', en: 'Request rejected' },
  request_cancelled: { ru: 'Заявка отменена', kz: 'Өтінім бас тартылды', en: 'Request cancelled' },
};

// Notification types the UI should visually flag as needing the
// organizer's attention, not just informational — currently just the one
// the brief calls out explicitly (section 22). Kept as its own lookup
// rather than a field on the notification itself, since "what counts as
// actionable" is presentation, not domain data.
const ACTION_REQUIRED_TYPES = new Set(['request_changes_requested']);

export function notificationActionRequired(notification) {
  return ACTION_REQUIRED_TYPES.has(notification.type);
}

const VOTE_LABEL = {
  up: { ru: '«За»', kz: '«Жақтап»', en: '"Yes"' },
  maybe: { ru: '«Подумать»', kz: '«Ойлану керек»', en: '"Maybe"' },
  down: { ru: '«Против»', kz: '«Қарсы»', en: '"No"' },
};

export function notificationTitle(notification, lang) {
  const t = TITLES[notification.type];
  if (!t) return notification.type;
  return t[lang] || t.ru;
}

export function notificationMessage(notification, lang) {
  const p = notification.payload || {};
  const actor = notification.actor?.name || (lang === 'kz' ? 'Жүйе' : lang === 'en' ? 'System' : 'Система');
  const price = (v) => formatPrice(v || 0);
  const vote = VOTE_LABEL[p.value]?.[lang] || VOTE_LABEL[p.value]?.ru || '';

  const templates = {
    invitation_accepted: {
      ru: `${actor} присоединился(лась) к вашей команде`,
      kz: `${actor} сіздің командаңызға қосылды`,
      en: `${actor} joined your team`,
    },
    candidate_added: {
      ru: `${actor} добавил(а) «${p.name}» — ${price(p.price)}`,
      kz: `${actor} «${p.name}» қосты — ${price(p.price)}`,
      en: `${actor} added "${p.name}" — ${price(p.price)}`,
    },
    vote_added: {
      ru: `${actor} проголосовал(а) ${vote} за «${p.name}»`,
      kz: `${actor} «${p.name}» үшін ${vote} дауыс берді`,
      en: `${actor} voted ${vote} for "${p.name}"`,
    },
    vote_changed: {
      ru: `${actor} изменил(а) голос на ${vote} за «${p.name}»`,
      kz: `${actor} «${p.name}» бойынша дауысын ${vote} етіп өзгертті`,
      en: `${actor} changed their vote to ${vote} for "${p.name}"`,
    },
    comment_added: {
      ru: p.candidate_name ? `${actor} прокомментировал(а) «${p.candidate_name}»` : `${actor} написал(а) в общем обсуждении`,
      kz: p.candidate_name ? `${actor} «${p.candidate_name}» бойынша пікір қалдырды` : `${actor} жалпы талқылауда пікір қалдырды`,
      en: p.candidate_name ? `${actor} commented on "${p.candidate_name}"` : `${actor} posted in the discussion`,
    },
    budget_updated: {
      ru: `${actor} изменил(а) бюджет на ${price(p.budget_total)}`,
      kz: `${actor} бюджетті ${price(p.budget_total)} етіп өзгертті`,
      en: `${actor} updated the budget to ${price(p.budget_total)}`,
    },
    task_created: {
      ru: `${actor} назначил(а) вам задачу «${p.title}»`,
      kz: `${actor} сізге «${p.title}» тапсырмасын тағайындады`,
      en: `${actor} assigned you the task "${p.title}"`,
    },
    task_updated: {
      ru: `${actor} изменил(а) задачу «${p.title}»`,
      kz: `${actor} «${p.title}» тапсырмасын өзгертті`,
      en: `${actor} updated the task "${p.title}"`,
    },
    task_completed: {
      ru: `${actor} выполнил(а) задачу «${p.title}»`,
      kz: `${actor} «${p.title}» тапсырмасын орындады`,
      en: `${actor} completed the task "${p.title}"`,
    },
    member_joined: {
      ru: `${actor} присоединился(лась) к мероприятию`,
      kz: `${actor} іс-шараға қосылды`,
      en: `${actor} joined the event`,
    },
    member_role_changed: {
      ru: `${actor} изменил(а) вашу роль на «${roleLabel(p.role, lang)}»`,
      kz: `${actor} сіздің рөліңізді «${roleLabel(p.role, lang)}» етіп өзгертті`,
      en: `${actor} changed your role to "${roleLabel(p.role, lang)}"`,
    },

    // 10B — the actor here is always an admin/manager, or (for
    // submitted/resubmitted/cancelled) the organizer — never "you" talking
    // to yourself, since createNotification already excludes self-notify.
    request_submitted: {
      ru: `Мероприятие «${notification.event?.title || ''}» отправлено на рассмотрение`,
      kz: `«${notification.event?.title || ''}» іс-шарасы қарауға жіберілді`,
      en: `The request for "${notification.event?.title || ''}" was submitted for review`,
    },
    request_resubmitted: {
      ru: `Организатор отправил версию №${p.revision ?? ''}`,
      kz: `Ұйымдастырушы №${p.revision ?? ''} нұсқасын жіберді`,
      en: `The organizer submitted revision #${p.revision ?? ''}`,
    },
    request_in_review: {
      ru: 'Менеджер MEREYTOI начал рассмотрение вашей заявки',
      kz: 'MEREYTOI менеджері өтінімді қарауды бастады',
      en: 'A MEREYTOI manager started reviewing your request',
    },
    request_changes_requested: {
      ru: `Менеджер просит уточнить заявку${p.manager_comment ? `: «${p.manager_comment}»` : ''}`,
      kz: `Менеджер өтінімді нақтылауды сұрайды${p.manager_comment ? `: «${p.manager_comment}»` : ''}`,
      en: `The manager asked for changes${p.manager_comment ? `: "${p.manager_comment}"` : ''}`,
    },
    request_approved: {
      ru: `MEREYTOI подтвердил вашу заявку${p.total ? ` — ${price(p.total)}` : ''}${p.booking_id ? ` · № ${p.booking_id}` : ''}`,
      kz: `MEREYTOI өтінімді растады${p.total ? ` — ${price(p.total)}` : ''}${p.booking_id ? ` · № ${p.booking_id}` : ''}`,
      en: `MEREYTOI approved your request${p.total ? ` — ${price(p.total)}` : ''}${p.booking_id ? ` · #${p.booking_id}` : ''}`,
    },
    request_rejected: {
      ru: `Менеджер MEREYTOI отклонил заявку${p.manager_comment ? `: «${p.manager_comment}»` : ''}`,
      kz: `MEREYTOI менеджері өтінімді қабылдамады${p.manager_comment ? `: «${p.manager_comment}»` : ''}`,
      en: `MEREYTOI rejected the request${p.manager_comment ? `: "${p.manager_comment}"` : ''}`,
    },
    request_cancelled: {
      ru: `${actor} отменил(а) заявку`,
      kz: `${actor} өтінімнен бас тартты`,
      en: `${actor} cancelled the request`,
    },
  };

  const forType = templates[notification.type];
  if (!forType) return notification.type;
  return forType[lang] || forType.ru;
}

// A small per-type glyph for the dropdown/list row — the rest of this site
// already uses plain emoji as icons everywhere (see Header.jsx) rather
// than an icon library, so this stays consistent with that instead of
// introducing one just for this.
const TYPE_ICONS = {
  invitation_accepted: '🤝',
  candidate_added: '🎯',
  vote_added: '🗳️',
  vote_changed: '🗳️',
  comment_added: '💬',
  budget_updated: '💰',
  task_created: '✅',
  task_updated: '✅',
  task_completed: '✅',
  member_joined: '🤝',
  member_role_changed: '🔧',
  request_submitted: '📨',
  request_resubmitted: '📨',
  request_in_review: '🔍',
  request_changes_requested: '✍️',
  request_approved: '✅',
  request_rejected: '⛔',
  request_cancelled: '🚫',
};

export function notificationTypeIcon(type) {
  return TYPE_ICONS[type] || '🔔';
}

// ---- Grouping repeated comment_added notifications ------------------
//
// Root cause of the "Nurlan wrote a comment ×3" spam: event_comment_handler.go's
// AddComment fans a fresh Notification row out to every other member on
// *every single* comment — correct backend behavior (each is a real,
// independent event), but three quick messages in the same thread produce
// three near-identical rows. Rather than changing that backend fan-out
// (more rows is harmless/more auditable; the complaint is purely about
// how they're *displayed*), this collapses same-conversation bursts into
// one row client-side, for whichever list renders through it (the bell
// dropdown and the full /profile/notifications page both do).
//
// Deliberately narrow: only comment_added ever collapses. Every other
// type (votes, tasks, budget, invitations, requests...) always renders as
// its own row — grouping is keyed by (type, event_id, entity_type,
// entity_id), so a vote burst on the same candidate *could* collapse the
// same way in the future, but nothing today ever mixes two different
// types into one card (brief section 6).
export function groupNotifications(notifications) {
  const order = [];
  const byKey = new Map();

  for (const n of notifications) {
    if (n.type !== 'comment_added') {
      order.push({ kind: 'single', notification: n });
      continue;
    }
    const key = `${n.type}:${n.event_id}:${n.entity_type}:${n.entity_id ?? ''}`;
    let bucket = byKey.get(key);
    if (!bucket) {
      bucket = { kind: 'group', key, items: [] };
      byKey.set(key, bucket);
      order.push(bucket);
    }
    bucket.items.push(n);
  }

  return order.map((entry) => {
    if (entry.kind === 'single' || entry.items.length === 1) {
      return { kind: 'single', notification: entry.kind === 'single' ? entry.notification : entry.items[0] };
    }
    // Input is already created_at-desc (both API list endpoints order that
    // way); items were pushed in that same order, so items[0] is latest.
    const items = entry.items;
    const latest = items[0];
    const isRead = items.every((n) => n.is_read);
    const actorNames = [...new Set(items.map((n) => n.actor?.name).filter(Boolean))];
    return { kind: 'group', key: entry.key, items, latest, isRead, actorNames, count: items.length };
  });
}

function ruPlural(n, one, few, many) {
  const mod10 = n % 10;
  const mod100 = n % 100;
  if (mod10 === 1 && mod100 !== 11) return one;
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) return few;
  return many;
}

// Two shapes, chosen by how many distinct people are in the burst — both
// are the two options this fix was asked to weigh, kept side by side
// since real data can land either way: "Nurlan: 3 новых сообщения" reads
// better for one chatty participant, "3 новых сообщения в обсуждении" +
// "Nurlan и ещё 1 участник" reads better once several people are involved.
export function notificationGroupTitle(group, lang) {
  const n = group.count;
  if (group.actorNames.length <= 1) {
    const actor = group.actorNames[0] || (lang === 'kz' ? 'Жүйе' : lang === 'en' ? 'System' : 'Система');
    if (lang === 'kz') return `${actor}: ${n} жаңа хабарлама`;
    if (lang === 'en') return `${actor}: ${n} new message${n === 1 ? '' : 's'}`;
    return `${actor}: ${n} ${ruPlural(n, 'новое сообщение', 'новых сообщения', 'новых сообщений')}`;
  }
  if (lang === 'kz') return `${n} жаңа хабарлама`;
  if (lang === 'en') return `${n} new messages`;
  return `${n} ${ruPlural(n, 'новое сообщение', 'новых сообщения', 'новых сообщений')} в обсуждении`;
}

export function notificationGroupSubtitle(group, lang) {
  if (group.actorNames.length <= 1) return '';
  const [first, ...rest] = group.actorNames;
  const extra = rest.length;
  if (lang === 'kz') return extra > 0 ? `${first} және тағы ${extra} қатысушы` : first;
  if (lang === 'en') return extra > 0 ? `${first} and ${extra} more` : first;
  const extraWord = extra === 1 ? 'участник' : extra >= 2 && extra <= 4 ? 'участника' : 'участников';
  return extra > 0 ? `${first} и ещё ${extra} ${extraWord}` : first;
}

// Shared by both the dropdown and the full list: what clicking a row (or
// group) should mark read and where it should navigate. A group marks
// every still-unread item within it, not just the newest.
export function notificationClickTargets(item, opts) {
  const latest = item.kind === 'group' ? item.latest : item.notification;
  const unreadIds = item.kind === 'group'
    ? item.items.filter((n) => !n.is_read).map((n) => n.id)
    : (latest.is_read ? [] : [latest.id]);
  return { unreadIds, route: notificationRoute(latest, opts) };
}

// Maps a notification's structured refs (type/event_id/entity_type/
// entity_id) to a real, current route — never a stored URL, so a later
// route rename can't leave old notifications pointing at a dead link
// (brief section 15). `isAdmin` disambiguates the one case where the same
// type reaches two different audiences with two different destinations:
// request_submitted/resubmitted/cancelled can land in either an admin's or
// an organizer/member's notification list, and each needs its own page —
// the notification itself is just a pointer either way, never a bypass of
// the real per-page auth checks (backend section 25).
export function notificationRoute(notification, { isAdmin = false } = {}) {
  const eventId = notification.event_id;
  const base = eventId ? `/profile/events/${eventId}` : null;

  switch (notification.type) {
    case 'vote_added':
    case 'vote_changed':
    case 'candidate_added':
      return base ? `${base}/services` : '/profile/notifications';
    case 'comment_added':
      if (!base) return '/profile/notifications';
      return notification.entity_type === 'candidate' ? `${base}/services` : `${base}/discussion`;
    case 'budget_updated':
      return base ? `${base}/budget` : '/profile/notifications';
    case 'task_created':
    case 'task_updated':
    case 'task_completed':
      return base ? `${base}/tasks` : '/profile/notifications';
    case 'invitation_accepted':
    case 'member_joined':
    case 'member_role_changed':
      return base ? `${base}/members` : '/profile/notifications';

    // 10B
    case 'request_submitted':
    case 'request_resubmitted':
      return notification.entity_id ? `/admin/event-requests/${notification.entity_id}` : '/admin/event-requests';
    case 'request_cancelled':
      // Admins get this one too (only when the request had already reached
      // them) — everyone else gets the workspace Request tab.
      return isAdmin && notification.entity_id
        ? `/admin/event-requests/${notification.entity_id}`
        : (base ? `${base}/request` : '/profile/notifications');
    case 'request_in_review':
    case 'request_changes_requested':
    case 'request_approved':
    case 'request_rejected':
      return base ? `${base}/request` : '/profile/notifications';

    default:
      return base || '/profile/notifications';
  }
}
