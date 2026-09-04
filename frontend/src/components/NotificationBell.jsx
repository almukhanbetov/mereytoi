'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/context/AuthContext';
import { useAdminAuth } from '@/context/AdminAuthContext';
import { T, useLang } from '@/context/AppProviders';
import { notificationsApi } from '@/lib/notificationsApi';
import { notificationTitle, notificationMessage, notificationRoute, notificationActionRequired } from '@/lib/notificationHelpers';
import { timeAgo } from '@/lib/eventHelpers';

// No WebSocket/SSE in this project yet (brief section 18) — a modest 60s
// poll keeps the badge count reasonably fresh without inventing realtime
// infrastructure for this stage. The full list is only ever fetched when
// the panel is actually opened.
const POLL_MS = 60000;

export default function NotificationBell() {
  const { isAuthenticated, user } = useAuth();
  // Safe to call unconditionally: on customer pages there's no
  // AdminAuthProvider ancestor, so this just reads the context's `null`
  // default — no error, no admin-only import needed to know that.
  const adminAuth = useAdminAuth();
  const authed = isAuthenticated || !!adminAuth?.isAdmin;
  const isAdmin = user?.role === 'admin' || !!adminAuth?.isAdmin;
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

  async function handleItemClick(n) {
    setOpen(false);
    if (!n.is_read) {
      setCount((c) => Math.max(0, c - 1));
      setNotifications((prev) => prev?.map((x) => (x.id === n.id ? { ...x, is_read: true } : x)) || null);
      notificationsApi.markRead(n.id).catch(() => {});
    }
    router.push(notificationRoute(n, { isAdmin }));
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
      <button type="button" className="cart-icon" onClick={handleToggle} aria-label="Уведомления / Хабарландырулар / Notifications">
        🔔
        {count > 0 && <span className="cart-icon__badge is-visible">{count > 99 ? '99+' : count}</span>}
      </button>

      {open && (
        <>
          <div className="notif-overlay" onClick={() => setOpen(false)} />
          <div className="notif-panel">
          <div className="notif-panel__head">
            <span className="notif-panel__title"><T ru="Уведомления" kz="Хабарландырулар" en="Notifications" /></span>
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
            {!loading && notifications?.map((n) => (
              <button
                type="button"
                key={n.id}
                className={`notif-item${!n.is_read ? ' is-unread' : ''}${notificationActionRequired(n) ? ' is-action-required' : ''}`}
                onClick={() => handleItemClick(n)}
              >
                <span className="notif-item__dot" />
                <span className="notif-item__body">
                  {notificationActionRequired(n) && (
                    <span className="notif-item__flag"><T ru="Требуется действие" kz="Әрекет қажет" en="Action required" /></span>
                  )}
                  <span className="notif-item__title">{notificationTitle(n, lang)}</span>
                  <span className="notif-item__message">{notificationMessage(n, lang)}</span>
                  <span className="notif-item__meta">
                    {n.event?.title ? `${n.event.title} · ` : ''}{timeAgo(n.created_at, lang)}
                  </span>
                </span>
              </button>
            ))}
          </div>

          <Link href="/profile/notifications" className="notif-panel__viewall" onClick={() => setOpen(false)}>
            <T ru="Все уведомления" kz="Барлық хабарландырулар" en="View all" />
          </Link>
          </div>
        </>
      )}
    </div>
  );
}
