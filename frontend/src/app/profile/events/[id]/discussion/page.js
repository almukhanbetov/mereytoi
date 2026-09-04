'use client';

import { T } from '@/context/AppProviders';
import { useEventWorkspace } from '@/context/EventWorkspaceContext';
import CommentThread from '@/components/profile/CommentThread';

export default function EventDiscussionPage() {
  const { eventId, canEdit } = useEventWorkspace();

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
