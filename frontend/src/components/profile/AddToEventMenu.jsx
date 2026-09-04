'use client';

import { useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import { useAuth } from '@/context/AuthContext';
import { T, useLang } from '@/context/AppProviders';
import { eventsApi } from '@/lib/eventsApi';

/** "Добавить в мой той" — a Pinterest-style quick-save popover on the
 * service detail page. Click an event to add this listing to its
 * shortlist immediately (no separate confirm step); a checkmark shows it's
 * already there. Logged-out visitors get a plain login prompt instead. */
export default function AddToEventMenu({ listingId }) {
  const { isAuthenticated } = useAuth();
  const { lang } = useLang();
  const [open, setOpen] = useState(false);
  const [events, setEvents] = useState(null);
  const [addedIds, setAddedIds] = useState([]);
  const ref = useRef(null);

  useEffect(() => {
    function handleClick(e) {
      if (ref.current && !ref.current.contains(e.target)) setOpen(false);
    }
    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, []);

  async function handleOpen() {
    setOpen((prev) => !prev);
    if (events === null && isAuthenticated) {
      const data = await eventsApi.list().catch(() => ({ events: [] }));
      setEvents(data.events || []);
    }
  }

  async function handleAdd(eventId) {
    try {
      await eventsApi.addCandidate(eventId, listingId);
      setAddedIds((prev) => [...prev, eventId]);
    } catch (err) {
      alert(err.message);
    }
  }

  if (!isAuthenticated) {
    return (
      <Link href="/login" className="btn btn--outline">
        <T ru="Войдите, чтобы добавить в мой той" kz="Тойыма қосу үшін кіріңіз" />
      </Link>
    );
  }

  return (
    <div className="ws-add-menu" ref={ref}>
      <button type="button" className="btn btn--outline" onClick={handleOpen} aria-expanded={open} aria-haspopup="true">
        + <T ru="Добавить в мой той" kz="Тойыма қосу" />
      </button>
      {open && (
        <div className="ws-add-menu__panel">
          {events === null && <div className="ws-skeleton" style={{ height: 60 }} />}
          {events?.length === 0 && (
            <p style={{ padding: '10px 12px', fontSize: 13, color: 'var(--text-muted)' }}>
              <T ru="У вас пока нет мероприятий" kz="Сізде әлі іс-шара жоқ" />
            </p>
          )}
          {events?.map((ev) => (
            <button
              key={ev.id}
              type="button"
              className={`ws-add-menu__item${addedIds.includes(ev.id) ? ' is-added' : ''}`}
              onClick={() => handleAdd(ev.id)}
              disabled={addedIds.includes(ev.id)}
            >
              <span>{ev.title}</span>
              <span>{addedIds.includes(ev.id) ? '✓' : '+'}</span>
            </button>
          ))}
          <Link href="/profile/events/new" className="ws-add-menu__new">
            + <T ru="Новое мероприятие" kz="Жаңа іс-шара" />
          </Link>
        </div>
      )}
    </div>
  );
}
