'use client';

import { useEffect } from 'react';
import { T } from '@/context/AppProviders';
import { useEventWorkspace } from '@/context/EventWorkspaceContext';
import { notificationsApi } from '@/lib/notificationsApi';
import CommentThread from '@/components/profile/CommentThread';

// How often to re-check for newly-arrived comment notifications while this
// tab stays open — comfortably faster than the bell's own ~12s badge poll,
// so the badge doesn't get a real chance to visibly tick up for a comment
// the user is already reading live in the thread below.
const SUPPRESS_POLL_MS = 5000;

export default function EventDiscussionPage() {
  const { eventId, canEdit } = useEventWorkspace();

  // Being on this exact event's general discussion tab means every
  // comment_added/"discussion" notification for THIS event is, by
  // definition, something the user is already seeing live in the thread
  // below (CommentThread has its own ~3s poll) — so it's marked read here
  // instead of sitting unread and padding out the bell badge/dropdown.
  //
  // Deliberately narrow: only (type=comment_added, entity_type=discussion,
  // this event_id). Per-candidate service-thread comments, and every other
  // notification type (invitations, tasks, requests, votes, budget) for
  // this same event are left completely untouched — being on this tab
  // says nothing about whether the user has seen those.
  useEffect(() => {
    let cancelled = false;

    async function suppress() {
      try {
        const data = await notificationsApi.list({ unread: true, limit: 50 });
        if (cancelled) return;
        const toMark = (data.notifications || []).filter(
          (n) => n.type === 'comment_added' && n.entity_type === 'discussion' && n.event_id === Number(eventId),
        );
        if (toMark.length === 0) return;
        await Promise.all(toMark.map((n) => notificationsApi.markRead(n.id)));
      } catch {
        // Best-effort — the badge just stays a little stale until the next
        // tick, or the next time this page is opened.
      }
    }

    suppress();
    const id = setInterval(suppress, SUPPRESS_POLL_MS);
    return () => { cancelled = true; clearInterval(id); };
  }, [eventId]);

  return (
    <div>
      <h2 className="ws-section-title"><T ru="Обсуждение" kz="Талқылау" /></h2>
      <p style={{ color: 'var(--text-muted)', fontSize: 13.5, marginTop: -12, marginBottom: 24 }}>
        <T
          ru="Здесь команда обсуждает организацию — это не чат с менеджером MEREYTOI."
          kz="Мұнда команда ұйымдастыруды талқылайды — бұл MEREYTOI менеджерімен чат емес."
        />
      </p>
      <CommentThread eventId={eventId} candidateId={null} canWrite={canEdit} />
    </div>
  );
}
