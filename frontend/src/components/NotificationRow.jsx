'use client';

import { T } from '@/context/AppProviders';
import {
  notificationTitle,
  notificationMessage,
  notificationActionRequired,
  notificationTypeIcon,
  notificationGroupTitle,
  notificationGroupSubtitle,
} from '@/lib/notificationHelpers';
import { timeAgo } from '@/lib/eventHelpers';

/** One row in either the bell dropdown or the full /profile/notifications
 * list — both render through this so the two can never quietly drift
 * apart. `item` is one entry from notificationHelpers.groupNotifications:
 * either `{ kind: 'single', notification }` or a collapsed comment burst
 * (`{ kind: 'group', items, latest, isRead, actorNames, count }`). */
export default function NotificationRow({ item, lang, onClick }) {
  const isGroup = item.kind === 'group';
  const latest = isGroup ? item.latest : item.notification;
  const isUnread = isGroup ? !item.isRead : !latest.is_read;
  const actionRequired = !isGroup && notificationActionRequired(latest);
  const subtitle = isGroup ? notificationGroupSubtitle(item, lang) : notificationMessage(latest, lang);

  return (
    <button
      type="button"
      className={`notif-item${isUnread ? ' is-unread' : ''}${actionRequired ? ' is-action-required' : ''}`}
      onClick={() => onClick(item)}
    >
      <span className="notif-item__icon">{notificationTypeIcon(latest.type)}</span>
      <span className="notif-item__dot" />
      <span className="notif-item__body">
        {actionRequired && (
          <span className="notif-item__flag"><T ru="Требуется действие" kz="Әрекет қажет" en="Action required" /></span>
        )}
        <span className="notif-item__title">
          {isGroup ? notificationGroupTitle(item, lang) : notificationTitle(latest, lang)}
        </span>
        {subtitle && <span className="notif-item__message">{subtitle}</span>}
        <span className="notif-item__meta">
          {latest.event?.title ? `${latest.event.title} · ` : ''}{timeAgo(latest.created_at, lang)}
        </span>
      </span>
    </button>
  );
}
