'use client';

import { useEffect, useState } from 'react';
import { useParams } from 'next/navigation';
import { adminApi } from '@/lib/adminApi';
import CategoryForm from '@/components/admin/CategoryForm';

export default function EditCategoryPage() {
  const { id } = useParams();
  const [category, setCategory] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    adminApi.categories()
      .then((d) => {
        const found = (d.categories || []).find((c) => String(c.id) === String(id));
        if (!found) setError('Категория не найдена');
        setCategory(found || null);
      })
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }, [id]);

  return (
    <div>
      <h1 className="admin-page-title">Изменить категорию</h1>
      {loading && <p className="admin-table__empty">Загрузка…</p>}
      {error && <p className="admin-login__error">{error}</p>}
      {category && <CategoryForm initial={category} categoryId={category.id} />}
    </div>
  );
}
