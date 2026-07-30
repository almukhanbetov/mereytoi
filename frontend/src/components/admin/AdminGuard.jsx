'use client';

import { useEffect } from 'react';
import { usePathname, useRouter } from 'next/navigation';
import { useAdminAuth } from '@/context/AdminAuthContext';
import AdminShell from '@/components/admin/AdminShell';

export default function AdminGuard({ children }) {
  const { user, loading, isAdmin } = useAdminAuth();
  const pathname = usePathname();
  const router = useRouter();
  const isLoginPage = pathname === '/admin/login';

  useEffect(() => {
    if (loading) return;
    if (!isAdmin && !isLoginPage) router.replace('/admin/login');
    if (isAdmin && isLoginPage) router.replace('/admin');
  }, [loading, isAdmin, isLoginPage, router]);

  if (isLoginPage) return children;

  if (loading || !isAdmin) {
    return (
      <div className="admin-loading">
        <span>Загрузка…</span>
      </div>
    );
  }

  return <AdminShell user={user}>{children}</AdminShell>;
}
