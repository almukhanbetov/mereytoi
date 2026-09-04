// Small shared helpers for the "Мой той" workspace — kept framework-free so
// both server and client components can import them.

export const EVENT_TYPES = ['wedding', 'toi', 'anniversary', 'corporate', 'other'];

export function eventTypeLabel(type, lang) {
  const ru = {
    wedding: 'Свадьба', toi: 'Той', anniversary: 'Юбилей', corporate: 'Корпоратив', other: 'Другое',
  };
  const kz = {
    wedding: 'Үйлену тойы', toi: 'Той', anniversary: 'Мерейтой', corporate: 'Корпоратив', other: 'Басқа',
  };
  const table = lang === 'kz' ? kz : ru;
  return table[type] || table.other;
}

export function eventTypeEmoji(type) {
  return { wedding: '💍', toi: '🎉', anniversary: '🥂', corporate: '🏢', other: '✨' }[type] || '✨';
}

export function roleLabel(role, lang) {
  const ru = { owner: 'Организатор', editor: 'Участник', viewer: 'Наблюдатель' };
  const kz = { owner: 'Ұйымдастырушы', editor: 'Қатысушы', viewer: 'Бақылаушы' };
  const en = { owner: 'Organizer', editor: 'Participant', viewer: 'Viewer' };
  const table = lang === 'kz' ? kz : lang === 'en' ? en : ru;
  return table[role] || role;
}

export function candidateStatusLabel(status, lang) {
  const ru = { shortlisted: 'Обсуждается', selected: 'Выбран', rejected: 'Отклонён' };
  const kz = { shortlisted: 'Талқылануда', selected: 'Таңдалды', rejected: 'Қабылданбады' };
  return (lang === 'kz' ? kz : ru)[status] || status;
}

export function formatEventDate(iso, lang) {
  if (!iso) return null;
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return null;
  const locale = lang === 'kz' ? 'kk-KZ' : lang === 'en' ? 'en-US' : 'ru-RU';
  return date.toLocaleDateString(locale, { day: 'numeric', month: 'long', year: 'numeric' });
}

// Returns null once the date has passed — "До мероприятия" only makes
// sense for a future date.
export function daysUntil(iso) {
  if (!iso) return null;
  const target = new Date(iso);
  if (Number.isNaN(target.getTime())) return null;
  const now = new Date();
  const diffMs = new Date(target.toDateString()) - new Date(now.toDateString());
  const days = Math.round(diffMs / 86400000);
  return days >= 0 ? days : null;
}

export function initials(name) {
  if (!name) return '?';
  const parts = name.trim().split(/\s+/).slice(0, 2);
  return parts.map((p) => p[0]?.toUpperCase() || '').join('') || '?';
}

// Renders one activity-feed line as "{actor}: {что произошло}" — a noun-
// phrase after the colon, deliberately, so it never has to pick a gendered
// Russian past-tense verb ending for an actor whose gender isn't known.
export function activityLine(entry, lang, formatPriceFn) {
  const payload = entry.payload || {};
  const actor = entry.actor?.name || (lang === 'kz' ? 'Жүйе' : 'Система');
  const price = (n) => (formatPriceFn ? formatPriceFn(n || 0) : `${n || 0} ₸`);
  const voteLabel = { up: lang === 'kz' ? '«Жақтап»' : '«За»', maybe: lang === 'kz' ? '«Ойлану керек»' : '«Подумать»', down: lang === 'kz' ? '«Қарсы»' : '«Против»' };

  const ru = {
    'event.created': `мероприятие создано`,
    'member.joined': `теперь в команде мероприятия`,
    'candidate.added': `добавлена услуга «${payload.name}» — ${price(payload.price)}`,
    'vote.cast': `голос ${voteLabel[payload.value] || ''} за «${payload.name}»`,
    'comment.added': payload.candidate_name ? `комментарий к «${payload.candidate_name}»` : 'комментарий в общем обсуждении',
    'candidate.selected': `выбрана услуга «${payload.name}» — ${price(payload.price)}`,
    'budget.updated': `бюджет изменён на ${price(payload.budget_total)}`,
    'task.created': `добавлена задача «${payload.title}»`,
    'task.completed': `задача «${payload.title}» выполнена`,
  };
  const kz = {
    'event.created': `іс-шара құрылды`,
    'member.joined': `енді іс-шара командасында`,
    'candidate.added': `«${payload.name}» қызметі қосылды — ${price(payload.price)}`,
    'vote.cast': `«${payload.name}» үшін ${voteLabel[payload.value] || ''} дауыс`,
    'comment.added': payload.candidate_name ? `«${payload.candidate_name}» бойынша пікір` : 'жалпы талқылауда пікір',
    'candidate.selected': `«${payload.name}» қызметі таңдалды — ${price(payload.price)}`,
    'budget.updated': `бюджет ${price(payload.budget_total)} болып өзгертілді`,
    'task.created': `«${payload.title}» тапсырмасы қосылды`,
    'task.completed': `«${payload.title}» тапсырмасы орындалды`,
  };
  const text = (lang === 'kz' ? kz : ru)[entry.verb] || entry.verb;
  return { actor, text };
}

export function formatDateTime(iso, lang) {
  if (!iso) return null;
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return null;
  const locale = lang === 'kz' ? 'kk-KZ' : lang === 'en' ? 'en-US' : 'ru-RU';
  return date.toLocaleString(locale, { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' });
}

export function timeAgo(iso, lang) {
  const date = new Date(iso);
  const diffSec = Math.floor((Date.now() - date.getTime()) / 1000);
  if (diffSec < 60) return lang === 'kz' ? 'жаңа ғана' : 'только что';
  const diffMin = Math.floor(diffSec / 60);
  if (diffMin < 60) return `${diffMin} ${lang === 'kz' ? 'мин' : 'мин'}`;
  const diffHr = Math.floor(diffMin / 60);
  if (diffHr < 24) return `${diffHr} ${lang === 'kz' ? 'сағ' : 'ч'}`;
  const diffDay = Math.floor(diffHr / 24);
  if (diffDay < 7) return `${diffDay} ${lang === 'kz' ? 'күн' : 'дн'}`;
  return date.toLocaleDateString(lang === 'kz' ? 'kk-KZ' : 'ru-RU', { day: '2-digit', month: '2-digit', year: 'numeric' });
}
