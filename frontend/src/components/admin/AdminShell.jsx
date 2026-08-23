'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useAdminAuth } from '@/context/AdminAuthContext';
import { useTheme } from '@/context/AppProviders';
import { adminApi } from '@/lib/adminApi';

export default function AdminShell({ user, children }) {
  const pathname = usePathname();
  const { logout } = useAdminAuth();
  const { toggleTheme } = useTheme();
  const [categories, setCategories] = useState([]);
  const [newBookings, setNewBookings] = useState(0);
  const [pendingComments, setPendingComments] = useState(0);

  useEffect(() => {
    adminApi.categories().then((d) => setCategories(d.categories || [])).catch(() => {});
    adminApi.bookings()
      .then((d) => setNewBookings((d.bookings || []).filter((b) => b.status === 'new').length))
      .catch(() => {});
    adminApi.comments(false)
      .then((d) => setPendingComments((d.comments || []).length))
      .catch(() => {});
  }, [pathname]);

  return (
    <div className="admin-shell">
      <aside className="admin-sidebar">
        <Link href="/admin" className="logo admin-sidebar__logo">
          <span className="logo__mark">M</span>
          <span className="logo__text">MEREY<em>TOI</em></span>
        </Link>

        <nav className="admin-nav">
          <Link href="/admin" className={`admin-nav__link${pathname === '/admin' ? ' is-active' : ''}`}>
            Дашборд
          </Link>
          <Link href="/admin/bookings" className={`admin-nav__link${pathname === '/admin/bookings' ? ' is-active' : ''}`}>
            <span>Заявки</span>
            {newBookings > 0 && <span className="admin-nav__badge">{newBookings}</span>}
          </Link>
          <Link href="/admin/comments" className={`admin-nav__link${pathname === '/admin/comments' ? ' is-active' : ''}`}>
            <span>Комментарии</span>
            {pendingComments > 0 && <span className="admin-nav__badge">{pendingComments}</span>}
          </Link>
          <Link href="/admin/clients" className={`admin-nav__link${pathname === '/admin/clients' ? ' is-active' : ''}`}>
            Клиенты
          </Link>
          <Link href="/admin/statistics" className={`admin-nav__link${pathname === '/admin/statistics' ? ' is-active' : ''}`}>
            Статистика
          </Link>

          <span className="admin-nav__label">Услуги</span>
          {categories.map((c) => {
            const href = `/admin/services/${c.slug}`;
            const active = pathname === href;
            return (
              <Link key={c.id} href={href} className={`admin-nav__link admin-nav__link--sub${active ? ' is-active' : ''}`}>
                {c.name_ru}
              </Link>
            );
          })}
        </nav>

        <div className="admin-sidebar__footer">
          <Link href="/" className="admin-nav__link" target="_blank">← На сайт</Link>
        </div>
      </aside>

      <div className="admin-main">
        <header className="admin-topbar">
          <div />
          <div className="admin-topbar__actions">
            <button className="theme-switch" onClick={toggleTheme} aria-label="Переключить тему">
              <span className="theme-switch__icon theme-switch__icon--sun">☀</span>
              <span className="theme-switch__icon theme-switch__icon--moon">☾</span>
            </button>
            <span className="admin-topbar__user">{user?.name || user?.email}</span>
            <button className="btn btn--outline btn--sm" onClick={logout}>Выйти</button>
          </div>
        </header>

        <main className="admin-content">{children}</main>
      </div>
    </div>
  );
}
