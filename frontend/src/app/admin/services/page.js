'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { adminApi } from '@/lib/adminApi';

export default function AdminServicesIndexPage() {
  const router = useRouter();

  useEffect(() => {
    adminApi.categories().then((d) => {
      const first = (d.categories || [])[0];
      router.replace(first ? `/admin/services/${first.slug}` : '/admin');
    });
  }, [router]);

  return <p className="admin-table__empty">Загрузка…</p>;
}
