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
};

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
  };

  const forType = templates[notification.type];
  if (!forType) return notification.type;
  return forType[lang] || forType.ru;
}

// Maps a notification's structured refs (type/event_id/entity_type/
// entity_id) to a real, current workspace route — never a stored URL, so a
// later route rename can't leave old notifications pointing at a dead link
// (brief section 15).
export function notificationRoute(notification) {
  const eventId = notification.event_id;
  if (!eventId) return '/profile/notifications';

  const base = `/profile/events/${eventId}`;
  switch (notification.type) {
    case 'vote_added':
    case 'vote_changed':
    case 'candidate_added':
      return `${base}/services`;
    case 'comment_added':
      return notification.entity_type === 'candidate' ? `${base}/services` : `${base}/discussion`;
    case 'budget_updated':
      return `${base}/budget`;
    case 'task_created':
    case 'task_updated':
    case 'task_completed':
      return `${base}/tasks`;
    case 'invitation_accepted':
    case 'member_joined':
    case 'member_role_changed':
      return `${base}/members`;
    default:
      return base;
  }
}
