'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/context/AuthContext';
import { T, useLang } from '@/context/AppProviders';
import { notificationsApi } from '@/lib/notificationsApi';
import { groupNotifications, notificationClickTargets } from '@/lib/notificationHelpers';
import NotificationRow from '@/components/NotificationRow';

// No WebSocket/SSE in this project yet — a short poll keeps the badge
// count reasonably fresh without inventing realtime infrastructure. The
// full list is only ever fetched when the panel is actually opened.
// Deliberately much slower than the ~3s discussion-message poll — a badge
// count doesn't need to feel instant the way a live chat does.
const POLL_MS = 12000;

// A simple "message circle" glyph (the collaborative workspace is
// fundamentally about discussion, so this reads better here than a bell)
// — drawn inline rather than pulling in an icon library for one icon.
// Uses currentColor so it picks up the gold tint from .cart-icon's own
// color the same way the header's theme-switch icon does.
function ChatIcon() {
  return (
    <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z" />
    </svg>
  );
}

export default function NotificationBell() {
  // 10C: this used to also check useAdminAuth() here, because an admin
  // session and a customer session were two separate token stores — an
  // admin-only login left `isAuthenticated` from useAuth() false even
  // though they were genuinely signed in. Auth is unified now (one shared
  // session backs both AdminAuthContext and AuthContext), so this same
  // component works correctly in both the site Header and AdminShell with
  // no admin-specific import at all.
  const { isAuthenticated: authed, user } = useAuth();
  const isAdmin = user?.role === 'admin';
  const { lang } = useLang();
  const router = useRouter();
  const wrapRef = useRef(null);

  const [open, setOpen] = useState(false);
  const [count, setCount] = useState(0);
  const [notifications, setNotifications] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const refreshCount = useCallback(() => {
    notificationsApi.unreadCount().then((d) => setCount(d.count || 0)).catch(() => {});
  }, []);

  useEffect(() => {
    if (!authed) return undefined;
    refreshCount();
    const id = setInterval(refreshCount, POLL_MS);
    return () => clearInterval(id);
  }, [authed, refreshCount]);

  useEffect(() => {
    function onOutside(e) {
      if (wrapRef.current && !wrapRef.current.contains(e.target)) setOpen(false);
    }
    document.addEventListener('mousedown', onOutside);
    return () => document.removeEventListener('mousedown', onOutside);
  }, []);

  async function handleToggle() {
    const next = !open;
    setOpen(next);
    if (next) {
      setLoading(true);
      setError('');
      try {
        const data = await notificationsApi.list({ limit: 8 });
        setNotifications(data.notifications || []);
      } catch (err) {
        setError(err.message);
      } finally {
        setLoading(false);
      }
    }
  }

  async function handleItemClick(item) {
    setOpen(false);
    const { unreadIds, route } = notificationClickTargets(item, { isAdmin });
    if (unreadIds.length > 0) {
      const idSet = new Set(unreadIds);
      setCount((c) => Math.max(0, c - unreadIds.length));
      setNotifications((prev) => prev?.map((x) => (idSet.has(x.id) ? { ...x, is_read: true } : x)) || null);
      Promise.all(unreadIds.map((id) => notificationsApi.markRead(id))).catch(() => {});
    }
    router.push(route);
  }

  async function handleMarkAll(e) {
    e.stopPropagation();
    try {
      await notificationsApi.markAllRead();
      setCount(0);
      setNotifications((prev) => prev?.map((n) => ({ ...n, is_read: true })) || null);
    } catch {
      // The badge just stays as-is — no alert(), the next open/poll will
      // reconcile it anyway.
    }
  }

  if (!authed) return null;

  return (
    <div className="notif-bell-wrap" ref={wrapRef}>
      <button type="button" className="cart-icon notif-bell-btn" onClick={handleToggle} aria-label="Активность / Белсенділік / Activity" aria-expanded={open} aria-haspopup="true">
        <ChatIcon />
        {count > 0 && <span className="cart-icon__badge is-visible">{count > 99 ? '99+' : count}</span>}
      </button>

      {open && (
        <>
          <div className="notif-overlay" onClick={() => setOpen(false)} />
          <div className="notif-panel">
          <div className="notif-panel__head">
            <span className="notif-panel__title"><T ru="Активность" kz="Белсенділік" en="Activity" /></span>
            {count > 0 && (
              <button type="button" className="notif-panel__markall" onClick={handleMarkAll}>
                <T ru="Прочитать всё" kz="Барлығын оқу" en="Mark all read" />
              </button>
            )}
          </div>

          <div className="notif-panel__list">
            {loading && <div className="ws-skeleton" style={{ height: 60, margin: '10px 14px' }} />}
            {!loading && error && <p className="notif-panel__empty">{error}</p>}
            {!loading && !error && notifications?.length === 0 && (
              <p className="notif-panel__empty"><T ru="Нет новых уведомлений" kz="Жаңа хабарландырулар жоқ" en="No new notifications" /></p>
            )}
            {!loading && groupNotifications(notifications || []).map((item) => (
              <NotificationRow
                key={item.kind === 'group' ? item.key : item.notification.id}
                item={item}
                lang={lang}
                onClick={handleItemClick}
              />
            ))}
          </div>

          <Link href="/profile/notifications" className="notif-panel__viewall" onClick={() => setOpen(false)}>
            <T ru="Вся активность" kz="Барлық белсенділік" en="All activity" />
          </Link>
          </div>
        </>
      )}
    </div>
  );
}
