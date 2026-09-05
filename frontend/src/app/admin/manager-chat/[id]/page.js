'use client';

import { use, useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { adminApi } from '@/lib/adminApi';
import { formatEventDate } from '@/lib/eventHelpers';
import { formatPrice } from '@/lib/format';

// Same cadence as the customer widget's own chat poll — a support inbox,
// not a live team discussion (brief section 9's "10-15s is enough" spirit
// applied here too even though it was written for notifications).
const POLL_MS = 10000;

function formatTime(iso) {
  return new Date(iso).toLocaleString('ru-RU', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });
}

export default function AdminManagerChatDetailPage({ params }) {
  const { id } = use(params);
  const [data, setData] = useState(null);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [reply, setReply] = useState('');
  const [sending, setSending] = useState(false);

  const load = useCallback(() => adminApi.managerChat(id).then(setData).catch((err) => setError(err.message)), [id]);

  useEffect(() => { load().finally(() => setLoading(false)); }, [load]);

  useEffect(() => {
    const interval = setInterval(() => {
      if (!document.hidden) load();
    }, POLL_MS);
    return () => clearInterval(interval);
  }, [load]);

  async function handleReply(e) {
    e.preventDefault();
    const body = reply.trim();
    if (!body || sending) return;
    setSending(true);
    setError('');
    try {
      await adminApi.replyManagerChat(id, body);
      setReply('');
      await load();
    } catch (err) {
      setError(err.message || 'Не удалось отправить ответ');
    } finally {
      setSending(false);
    }
  }

  async function handleStatusToggle() {
    const next = data.conversation.status === 'closed' ? 'open' : 'closed';
    try {
      await adminApi.updateManagerChatStatus(id, next);
      await load();
    } catch (err) {
      setError(err.message || 'Не удалось изменить статус');
    }
  }

  if (loading) return <p className="admin-table__empty">Загрузка…</p>;
  if (!data) return <p className="admin-table__empty">{error || 'Диалог не найден'}</p>;

  const { conversation, messages } = data;

  return (
    <div>
      <Link href="/admin/manager-chat" className="admin-table__link">← Все диалоги</Link>
      <h1 className="admin-page-title">{conversation.user?.name || '—'}</h1>
      <p className="admin-table__empty" style={{ margin: '0 0 20px', textAlign: 'left' }}>
        {conversation.user?.email}{conversation.user?.phone ? ` · ${conversation.user.phone}` : ''}
      </p>

      {(conversation.event || conversation.listing) && (
        <div className="admin-stat-card" style={{ display: 'block', marginBottom: 24, maxWidth: 420 }}>
          {conversation.event && (
            <>
              <div className="admin-stat-card__label">Мероприятие</div>
              <div className="admin-stat-card__num" style={{ fontSize: 17 }}>{conversation.event.title}</div>
              <p className="admin-table__empty" style={{ textAlign: 'left', margin: '4px 0 0' }}>
                {formatEventDate(conversation.event.event_date, 'ru') || 'дата не указана'} · {conversation.event.city || '—'} · {conversation.event.guests || 0} гостей
                {conversation.event.budget_total > 0 && ` · Бюджет: ${formatPrice(conversation.event.budget_total)}`}
              </p>
              {/* Brief section 22: no link to the event workspace here — an
                  admin has no EventMember access to /profile/events/:id, so
                  nothing clickable is offered for a page they can't open. */}
            </>
          )}
          {conversation.listing && (
            <>
              <div className="admin-stat-card__label" style={{ marginTop: conversation.event ? 14 : 0 }}>Услуга</div>
              <div className="admin-stat-card__num" style={{ fontSize: 17 }}>{conversation.listing.name_ru}</div>
              {conversation.listing.price > 0 && (
                <p className="admin-table__empty" style={{ textAlign: 'left', margin: '4px 0 0' }}>{formatPrice(conversation.listing.price)}</p>
              )}
              <Link href={`/services/${conversation.listing.id}`} className="admin-table__link" target="_blank" style={{ display: 'inline-block', marginTop: 6 }}>
                Открыть услугу →
              </Link>
            </>
          )}
        </div>
      )}

      <div className="manager-chat-admin-thread">
        {messages.length === 0 && <p className="admin-table__empty">Сообщений пока нет</p>}
        {messages.map((m) => (
          <div className={`manager-chat-msg manager-chat-msg--${m.sender_type === 'manager' ? 'out' : 'in'}`} key={m.id} style={{ maxWidth: '70%' }}>
            <p className="manager-chat-msg__text">{m.body}</p>
            <span className="manager-chat-msg__time">{formatTime(m.created_at)}</span>
          </div>
        ))}
      </div>

      {error && <p className="admin-login__error">{error}</p>}

      <form onSubmit={handleReply} style={{ display: 'flex', gap: 10, marginBottom: 20 }}>
        <textarea
          value={reply}
          onChange={(e) => setReply(e.target.value)}
          rows={2}
          placeholder="Ответить…"
          style={{ flex: 1, padding: '12px 16px', borderRadius: 10, border: '1px solid var(--border)', background: 'var(--input-bg)', color: 'var(--text)', fontFamily: 'inherit', fontSize: 14, resize: 'vertical' }}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); handleReply(e); }
          }}
        />
        <button type="submit" className="btn btn--gold" disabled={sending || !reply.trim()}>Отправить</button>
      </form>

      <button type="button" className="btn btn--outline" style={{ padding: '10px 18px', fontSize: 13.5 }} onClick={handleStatusToggle}>
        {conversation.status === 'closed' ? 'Открыть диалог заново' : 'Закрыть диалог'}
      </button>
    </div>
  );
}
