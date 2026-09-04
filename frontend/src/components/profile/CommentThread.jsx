'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { useAuth } from '@/context/AuthContext';
import { T, useLang } from '@/context/AppProviders';
import { eventsApi } from '@/lib/eventsApi';
import { initials, timeAgo } from '@/lib/eventHelpers';
import InlineNotice from '@/components/profile/InlineNotice';

// Background refresh cadence for "someone else posted" — no realtime
// infrastructure (WebSocket/SSE) exists in this project yet, so this is a
// deliberately short poll instead, per the fix's own brief.
const POLL_MS = 3000;
// "Near the bottom" threshold (px) used to decide whether a newly-polled
// message should auto-scroll the thread or just raise the "new messages"
// pill — matches ordinary chat-UI convention (a little slack for sub-pixel
// rounding / the last message's own height).
const BOTTOM_THRESHOLD = 80;

const isTemp = (id) => typeof id === 'string' && id.startsWith('tmp-');

// One shared ordering rule for every code path that touches `comments` —
// polling, optimistic insert, and the server response that resolves it —
// so nothing can ever quietly disagree on order. Ties on created_at (which
// can genuinely collide at second resolution) fall back to numeric id;
// still-unconfirmed optimistic entries (string "tmp-" ids) always sort
// after every real id with the same timestamp.
function sortComments(list) {
  return [...list].sort((a, b) => {
    const ta = new Date(a.created_at).getTime();
    const tb = new Date(b.created_at).getTime();
    if (ta !== tb) return ta - tb;
    const na = typeof a.id === 'number' ? a.id : Number.MAX_SAFE_INTEGER;
    const nb = typeof b.id === 'number' ? b.id : Number.MAX_SAFE_INTEGER;
    return na - nb;
  });
}

/** The comment/discussion thread — reused as-is both inline on the
 * "Обсуждение" tab (candidateId=null) and inside a modal for a single
 * shortlisted service's thread (candidateId set). Optimistic add/delete so
 * the workspace feels immediate without any realtime infrastructure;
 * other participants' messages arrive via a short poll (see POLL_MS) since
 * this project has no WebSocket/SSE — see the fix-up report for why a
 * manual refresh was previously required. */
export default function CommentThread({ eventId, candidateId = null, canWrite }) {
  const { user } = useAuth();
  const { lang } = useLang();
  const [comments, setComments] = useState([]);
  const [loading, setLoading] = useState(true);
  const [text, setText] = useState('');
  const [sending, setSending] = useState(false);
  const [sendError, setSendError] = useState('');
  const [hasNewBelow, setHasNewBelow] = useState(false);

  const scrollRef = useRef(null);
  // Whether the user was scrolled near the bottom the last time we
  // checked — read inside the poll's setState updater, so it must be a
  // ref (a plain closure over state would see a stale value by the time
  // the interval fires).
  const nearBottomRef = useRef(true);
  // 'instant' | 'smooth' | null — consumed by the effect below, right
  // after the comments list actually re-renders with new content.
  const pendingScrollRef = useRef(null);
  // Comment ids currently being deleted optimistically — kept out of the
  // *next* poll's merge so a delete never visibly "flashes back" for the
  // ~1s it takes the DELETE request to land server-side.
  const pendingDeleteIdsRef = useRef(new Set());

  const scrollToBottom = useCallback((behavior) => {
    const el = scrollRef.current;
    if (!el) return;
    el.scrollTo({ top: el.scrollHeight, behavior });
  }, []);

  const load = useCallback(async () => {
    try {
      const data = await eventsApi.comments(eventId, candidateId);
      setComments(sortComments(data.comments || []));
      pendingScrollRef.current = 'instant';
    } finally {
      setLoading(false);
    }
  }, [eventId, candidateId]);

  useEffect(() => { load(); }, [load]);

  // ---- Background polling for other participants' messages ----------
  // Deliberately scoped to this component's own lifetime: it only ever
  // runs while a CommentThread is actually mounted (the "Обсуждение" tab
  // is open, or a candidate's comment modal is open), and is torn down on
  // unmount/eventId/candidateId change — there is no separate "is this
  // tab active" flag to manage beyond React's normal mount/unmount.
  useEffect(() => {
    let cancelled = false;

    async function poll() {
      // Best-effort pause while the browser tab itself isn't visible —
      // no point spending a request on a chat nobody is looking at. The
      // interval keeps ticking (simpler than tearing it down/recreating
      // it) — each tick just no-ops until the tab is visible again.
      if (document.hidden) return;
      try {
        const data = await eventsApi.comments(eventId, candidateId);
        if (cancelled) return;
        const fresh = (data.comments || []).filter((c) => !pendingDeleteIdsRef.current.has(c.id));

        setComments((prev) => {
          const prevRealIds = new Set(prev.filter((c) => !isTemp(c.id)).map((c) => c.id));
          const newReal = fresh.filter((c) => !prevRealIds.has(c.id));

          // Still-sending placeholder from this client — normally left
          // alone until handleSend's own POST response reconciles it by
          // id. The one race this can't cover: our own message already
          // committed server-side (so it just showed up in `newReal`)
          // before that POST response reached us. Matching by author+text
          // catches that specific case so a fast poll tick can never
          // render our own message twice, even for one frame.
          const stillPending = prev
            .filter((c) => isTemp(c.id))
            .filter((p) => !newReal.some((r) => r.user_id === p.user_id && r.body === p.body));

          const merged = sortComments([...fresh, ...stillPending]);

          const isFromSomeoneElse = newReal.some((c) => c.user_id !== user?.id);
          if (isFromSomeoneElse) {
            if (nearBottomRef.current) pendingScrollRef.current = 'smooth';
            else setHasNewBelow(true);
          }
          return merged;
        });
      } catch {
        // A transient network hiccup shouldn't surface as an error banner
        // for a background refresh — the next tick just tries again.
      }
    }

    const id = setInterval(poll, POLL_MS);
    // Catch up immediately (rather than waiting up to POLL_MS) when the
    // tab regains focus/visibility — directly serves the "B sees it
    // within 3-4s" requirement even if B had briefly tabbed away.
    function onVisible() {
      if (!document.hidden) poll();
    }
    document.addEventListener('visibilitychange', onVisible);

    return () => {
      cancelled = true;
      clearInterval(id);
      document.removeEventListener('visibilitychange', onVisible);
    };
    // Deliberately not depending on the full `comments` array — it reads
    // the latest state via the setComments updater instead, so a new
    // message doesn't tear down and recreate the interval. `user?.id` is
    // a stable primitive for the session, included only so poll() always
    // closes over the current value rather than one captured at mount.
  }, [eventId, candidateId, user?.id]);

  // Runs after the comments list actually changes in the DOM — consumes
  // whatever scroll intent the load/poll/send paths queued above.
  useEffect(() => {
    if (!pendingScrollRef.current) return;
    const behavior = pendingScrollRef.current === 'instant' ? 'auto' : 'smooth';
    pendingScrollRef.current = null;
    scrollToBottom(behavior);
  }, [comments, scrollToBottom]);

  function handleScroll() {
    const el = scrollRef.current;
    if (!el) return;
    const distanceFromBottom = el.scrollHeight - el.scrollTop - el.clientHeight;
    const nowNearBottom = distanceFromBottom < BOTTOM_THRESHOLD;
    nearBottomRef.current = nowNearBottom;
    if (nowNearBottom) setHasNewBelow(false);
  }

  function handleJumpToNew() {
    setHasNewBelow(false);
    pendingScrollRef.current = 'smooth';
    // comments hasn't changed, so the effect above won't fire on its own —
    // scroll directly.
    scrollToBottom('smooth');
  }

  async function handleSend(e) {
    e.preventDefault();
    const body = text.trim();
    if (!body || sending) return;
    setSending(true);
    setSendError('');
    setText('');
    const tempId = `tmp-${Date.now()}`;
    const optimistic = { id: tempId, body, user: { name: user?.name }, user_id: user?.id, created_at: new Date().toISOString() };
    // Sending is always "your own" action — scroll to it regardless of
    // where the user was reading, same as any chat UI.
    setComments((prev) => sortComments([...prev, optimistic]));
    pendingScrollRef.current = 'smooth';
    try {
      const { comment } = await eventsApi.addComment(eventId, body, candidateId);
      setComments((prev) => {
        // A poll can in principle land the real row (same id) before this
        // POST resolves — filter both the temp placeholder AND any
        // already-polled copy of the same id, then add the authoritative
        // one once, so this can never produce a visible duplicate.
        const withoutThisMessage = prev.filter((c) => c.id !== tempId && c.id !== comment.id);
        return sortComments([...withoutThisMessage, comment]);
      });
    } catch (err) {
      // Roll back to exactly "no optimistic entry" and restore the text
      // the user typed, rather than silently discarding it.
      setComments((prev) => prev.filter((c) => c.id !== tempId));
      setText(body);
      setSendError(err.message || (lang === 'kz' ? 'Хабарлама жіберілмеді' : 'Не удалось отправить сообщение'));
    } finally {
      setSending(false);
    }
  }

  async function handleDelete(id) {
    const confirmText = lang === 'kz' ? 'Хабарламаны жоясыз ба?' : 'Удалить сообщение?';
    if (!window.confirm(confirmText)) return;
    const prev = comments;
    pendingDeleteIdsRef.current.add(id);
    setComments((cur) => cur.filter((c) => c.id !== id));
    try {
      await eventsApi.deleteComment(eventId, id);
    } catch (err) {
      setComments(prev);
      alert(err.message);
    } finally {
      pendingDeleteIdsRef.current.delete(id);
    }
  }

  return (
    <div>
      <div className="ws-thread-wrap">
        <div className="ws-thread ws-thread--scroll" ref={scrollRef} onScroll={handleScroll}>
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
                  {c.user_id === user?.id && !isTemp(c.id) && (
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

        {hasNewBelow && (
          <button type="button" className="ws-thread-newpill" onClick={handleJumpToNew}>
            <T ru="Новые сообщения ↓" kz="Жаңа хабарламалар ↓" en="New messages ↓" />
          </button>
        )}
      </div>

      {canWrite && (
        <>
          <InlineNotice type="error">{sendError}</InlineNotice>
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
        </>
      )}
    </div>
  );
}
