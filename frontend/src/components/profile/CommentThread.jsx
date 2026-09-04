'use client';

import { useCallback, useEffect, useState } from 'react';
import { useAuth } from '@/context/AuthContext';
import { T, useLang } from '@/context/AppProviders';
import { eventsApi } from '@/lib/eventsApi';
import { initials, timeAgo } from '@/lib/eventHelpers';

/** The comment/discussion thread — reused as-is both inline on the
 * "Обсуждение" tab (candidateId=null) and inside a modal for a single
 * shortlisted service's thread (candidateId set). Optimistic add/delete so
 * the workspace feels immediate without any realtime infrastructure. */
export default function CommentThread({ eventId, candidateId = null, canWrite }) {
  const { user } = useAuth();
  const { lang } = useLang();
  const [comments, setComments] = useState([]);
  const [loading, setLoading] = useState(true);
  const [text, setText] = useState('');
  const [sending, setSending] = useState(false);

  const load = useCallback(async () => {
    try {
      const data = await eventsApi.comments(eventId, candidateId);
      setComments(data.comments || []);
    } finally {
      setLoading(false);
    }
  }, [eventId, candidateId]);

  useEffect(() => { load(); }, [load]);

  async function handleSend(e) {
    e.preventDefault();
    const body = text.trim();
    if (!body || sending) return;
    setSending(true);
    setText('');
    const tempId = `tmp-${Date.now()}`;
    const optimistic = { id: tempId, body, user: { name: user?.name }, user_id: user?.id, created_at: new Date().toISOString() };
    setComments((prev) => [...prev, optimistic]);
    try {
      const { comment } = await eventsApi.addComment(eventId, body, candidateId);
      setComments((prev) => prev.map((c) => (c.id === tempId ? comment : c)));
    } catch (err) {
      setComments((prev) => prev.filter((c) => c.id !== tempId));
      alert(err.message || (lang === 'kz' ? 'Хабарлама жіберілмеді' : 'Не удалось отправить сообщение'));
    } finally {
      setSending(false);
    }
  }

  async function handleDelete(id) {
    const confirmText = lang === 'kz' ? 'Хабарламаны жоясыз ба?' : 'Удалить сообщение?';
    if (!window.confirm(confirmText)) return;
    const prev = comments;
    setComments((cur) => cur.filter((c) => c.id !== id));
    try {
      await eventsApi.deleteComment(eventId, id);
    } catch (err) {
      setComments(prev);
      alert(err.message);
    }
  }

  return (
    <div>
      <div className="ws-thread">
        {loading && <div className="ws-skeleton" style={{ height: 70 }} />}
        {!loading && comments.length === 0 && (
          <p className="ws-empty__text" style={{ textAlign: 'left' }}>
            <T ru="Пока ничего не обсуждали — начните первым." kz="Әзірге ештеңе талқыланбады — бірінші болып бастаңыз." />
          </p>
        )}
        {comments.map((c) => (
          <div className="ws-message" key={c.id}>
            <div className="ws-avatar">{initials(c.user?.name)}</div>
            <div className="ws-message__body">
              <div className="ws-message__head">
                <span className="ws-message__author">{c.user?.name || '—'}</span>
                <span className="ws-message__time">{timeAgo(c.created_at, lang)}</span>
                {c.user_id === user?.id && (
                  <button type="button" className="ws-message__delete" onClick={() => handleDelete(c.id)}>
                    <T ru="Удалить" kz="Жою" />
                  </button>
                )}
              </div>
              <p className="ws-message__text">{c.body}</p>
            </div>
          </div>
        ))}
      </div>

      {canWrite && (
        <form className="ws-composer" onSubmit={handleSend}>
          <textarea
            rows={1}
            value={text}
            onChange={(e) => setText(e.target.value)}
            placeholder={lang === 'kz' ? 'Пікір жазу...' : 'Написать комментарий...'}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); handleSend(e); }
            }}
          />
          <button type="submit" className="btn btn--gold" disabled={sending || !text.trim()}>→</button>
        </form>
      )}
    </div>
  );
}
