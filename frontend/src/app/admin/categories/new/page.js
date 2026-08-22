'use client';

import { useEffect, useState } from 'react';
import { adminApi } from '@/lib/adminApi';
import CategoryForm from '@/components/admin/CategoryForm';

export default function NewCategoryPage() {
  const [nextPosition, setNextPosition] = useState(0);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    adminApi.categories()
      .then((d) => setNextPosition((d.categories || []).length + 1))
      .finally(() => setLoading(false));
  }, []);

  return (
    <div>
      <h1 className="admin-page-title">Новая категория</h1>
      {!loading && <CategoryForm initial={{ position: nextPosition }} />}
    </div>
  );
}
