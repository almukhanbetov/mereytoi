'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { adminApi } from '@/lib/adminApi';
import { formatEventDate } from '@/lib/eventHelpers';

function timeAgoRu(iso) {
  const diffMs = Date.now() - new Date(iso).getTime();
  const mins = Math.floor(diffMs / 60000);
  if (mins < 1) return 'сейчас';
  if (mins < 60) return `${mins} мин`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours} ч`;
  return new Date(iso).toLocaleDateString('ru-RU', { day: '2-digit', month: '2-digit' });
}

// The manager's dialog list (brief section 24) — deliberately not a CRM:
// exactly the columns the brief itself asked for, reusing the same
// booking-card-list visual language as /admin/bookings rather than
// inventing a new admin UI pattern for one more list.
export default function AdminManagerChatPage() {
  const [conversations, setConversations] = useState([]);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState('open');

  useEffect(() => {
    setLoading(true);
    adminApi.managerChats(statusFilter)
      .then((d) => setConversations(d.conversations || []))
      .finally(() => setLoading(false));
  }, [statusFilter]);

  return (
    <div>
      <h1 className="admin-page-title">Диалоги</h1>

      <div className="admin-filters">
        <select value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}>
          <option value="all">Все статусы</option>
          <option value="open">Открытые</option>
          <option value="closed">Закрытые</option>
        </select>
      </div>

      {loading && <p className="admin-table__empty">Загрузка…</p>}
      {!loading && conversations.length === 0 && <p className="admin-table__empty">Диалогов пока нет</p>}

      <div className="booking-list">
        {conversations.map((c) => (
          <Link href={`/admin/manager-chat/${c.id}`} className={`booking-card${c.status === 'closed' ? ' booking-card--cancelled' : ''}`} key={c.id}>
            <div className="booking-card__head">
              <div>
                <p className="booking-card__customer">{c.user?.name || '—'}</p>
                <span className="booking-card__phone">
                  {c.event?.title || (c.listing ? '' : 'Общий вопрос')}
                  {c.event && c.listing ? ' · ' : ''}
                  {c.listing ? c.listing.name_ru : ''}
                </span>
              </div>
              <div className="booking-card__meta">
                <span className="booking-card__date">{timeAgoRu(c.updated_at)}</span>
                {c.unread_count > 0 && <span className="manager-chat-dot" title="Есть непрочитанные" />}
              </div>
            </div>
            {c.last_message && (
              <p className="booking-card__message">«{c.last_message.body}»</p>
            )}
            <div className="booking-card__footer">
              <span>{c.event?.event_date ? formatEventDate(c.event.event_date, 'ru') : '—'}</span>
              <span>{c.status === 'closed' ? 'Закрыт' : 'Открыт'}</span>
            </div>
          </Link>
        ))}
      </div>
    </div>
  );
}
