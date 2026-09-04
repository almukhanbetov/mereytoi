'use client';

import { createContext, useCallback, useContext, useMemo, useState } from 'react';
import { eventsApi } from '@/lib/eventsApi';

const EventWorkspaceContext = createContext(null);

/** Everything a tab inside /profile/events/[id]/* needs, loaded once by the
 * shell layout and shared down — role-derived flags included, so pages
 * never have to re-derive "can I edit this" from a raw role string. */
export function EventWorkspaceProvider({ eventId, event, myRole, summary, children }) {
  const [currentEvent, setCurrentEvent] = useState(event);
  const [currentSummary, setCurrentSummary] = useState(summary);

  const refreshSummary = useCallback(async () => {
    try {
      const data = await eventsApi.summary(eventId);
      setCurrentSummary(data);
    } catch {
      // Summary is a "nice to have" refresh — a failed refetch shouldn't
      // interrupt whatever action the user just took.
    }
  }, [eventId]);

  const refreshEvent = useCallback(async () => {
    try {
      const data = await eventsApi.get(eventId);
      setCurrentEvent(data.event);
    } catch {
      // Same reasoning as refreshSummary.
    }
  }, [eventId]);

  const value = useMemo(() => {
    const rank = { owner: 3, editor: 2, viewer: 1 }[myRole] || 0;
    return {
      eventId,
      event: currentEvent,
      myRole,
      isOwner: myRole === 'owner',
      canEdit: rank >= 2,
      summary: currentSummary,
      refreshSummary,
      refreshEvent,
    };
  }, [eventId, currentEvent, myRole, currentSummary, refreshSummary, refreshEvent]);

  return <EventWorkspaceContext.Provider value={value}>{children}</EventWorkspaceContext.Provider>;
}

export function useEventWorkspace() {
  const ctx = useContext(EventWorkspaceContext);
  if (!ctx) throw new Error('useEventWorkspace must be used within an event workspace page');
  return ctx;
}
