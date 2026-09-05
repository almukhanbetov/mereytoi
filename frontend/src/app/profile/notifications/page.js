'use client';

import { useCallback, useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/context/AuthContext';
import { T, useLang } from '@/context/AppProviders';
import { notificationsApi } from '@/lib/notificationsApi';
import { groupNotifications, notificationClickTargets } from '@/lib/notificationHelpers';
import NotificationRow from '@/components/NotificationRow';

const PAGE_SIZE = 20;

export default function NotificationsPage() {
  const { isAuthenticated, loading: authLoading, user } = useAuth();
  const isAdmin = user?.role === 'admin';
  const { lang } = useLang();
  const router = useRouter();

  const [tab, setTab] = useState('all'); // 'all' | 'unread'
  const [page, setPage] = useState(1);
  const [notifications, setNotifications] = useState([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    if (!authLoading && !isAuthenticated) router.replace('/login?next=/profile/notifications');
  }, [authLoading, isAuthenticated, router]);

  const load = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const data = await notificationsApi.list({ unread: tab === 'unread', page, limit: PAGE_SIZE });
      setNotifications(data.notifications || []);
      setTotal(data.total || 0);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }, [tab, page]);

  useEffect(() => {
    if (isAuthenticated) load();
  }, [isAuthenticated, load]);

  function switchTab(next) {
    setTab(next);
    setPage(1);
  }

  async function handleClick(item) {
    const { unreadIds, route } = notificationClickTargets(item, { isAdmin });
    if (unreadIds.length > 0) {
      const idSet = new Set(unreadIds);
      setNotifications((prev) => prev.map((x) => (idSet.has(x.id) ? { ...x, is_read: true } : x)));
      Promise.all(unreadIds.map((id) => notificationsApi.markRead(id))).catch(() => {});
    }
    router.push(route);
  }

  async function handleMarkAll() {
    try {
      await notificationsApi.markAllRead();
      setNotifications((prev) => prev.map((n) => ({ ...n, is_read: true })));
    } catch (err) {
      setError(err.message);
    }
  }

  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));

  if (authLoading || !isAuthenticated) return null;

  return (
    <section className="page-hero" style={{ padding: '150px 0 100px' }}>
      <div className="hero__blob hero__blob--1"></div>
      <div className="container" style={{ maxWidth: 720 }}>
        <h1><T ru="Активность" kz="Белсенділік" en="Activity" /></h1>

        <div className="ws-tabs" role="tablist" style={{ marginTop: 26 }}>
          <button
            type="button"
            role="tab"
            aria-selected={tab === 'all'}
            className={`ws-tabs__btn${tab === 'all' ? ' is-active' : ''}`}
            onClick={() => switchTab('all')}
          >
            <T ru="Все" kz="Барлығы" en="All" />
          </button>
          <button
            type="button"
            role="tab"
            aria-selected={tab === 'unread'}
            className={`ws-tabs__btn${tab === 'unread' ? ' is-active' : ''}`}
            onClick={() => switchTab('unread')}
          >
            <T ru="Непрочитанные" kz="Оқылмаған" en="Unread" />
          </button>
        </div>

        <div style={{ display: 'flex', justifyContent: 'flex-end', marginBottom: 14 }}>
          <button type="button" className="admin-table__link" onClick={handleMarkAll}>
            <T ru="Прочитать всё" kz="Барлығын оқу" en="Mark all read" />
          </button>
        </div>

        {loading && <div className="ws-skeleton" style={{ height: 300 }} />}
        {!loading && error && <p className="auth-card__error">{error}</p>}

        {!loading && !error && notifications.length === 0 && (
          <div className="ws-empty">
            <span className="ws-empty__icon">🔔</span>
            <p className="ws-empty__text">
              <T ru="Нет новых уведомлений" kz="Жаңа хабарландырулар жоқ" en="No new notifications" />
            </p>
          </div>
        )}

        {!loading && !error && notifications.length > 0 && (
          <div style={{ background: 'var(--bg-card)', border: '1px solid var(--border)', borderRadius: 16, overflow: 'hidden' }}>
            {groupNotifications(notifications).map((item) => (
              <NotificationRow
                key={item.kind === 'group' ? item.key : item.notification.id}
                item={item}
                lang={lang}
                onClick={handleClick}
              />
            ))}
          </div>
        )}

        {!loading && totalPages > 1 && (
          <div style={{ display: 'flex', justifyContent: 'center', gap: 10, marginTop: 24 }}>
            <button type="button" className="btn btn--outline" style={{ padding: '8px 18px', fontSize: 13 }} disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>
              ←
            </button>
            <span style={{ alignSelf: 'center', color: 'var(--text-muted)', fontSize: 13 }}>{page} / {totalPages}</span>
            <button type="button" className="btn btn--outline" style={{ padding: '8px 18px', fontSize: 13 }} disabled={page >= totalPages} onClick={() => setPage((p) => p + 1)}>
              →
            </button>
          </div>
        )}
      </div>
    </section>
  );
}
