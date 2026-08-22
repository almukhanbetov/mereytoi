'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { adminApi } from '@/lib/adminApi';

export default function AdminDashboardPage() {
  const [categories, setCategories] = useState([]);
  const [listings, setListings] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    Promise.all([adminApi.categories(), adminApi.listings()])
      .then(([c, l]) => {
        setCategories(c.categories || []);
        setListings(l.listings || []);
      })
      .finally(() => setLoading(false));
  }, []);

  const byCategory = categories.map((c) => ({
    ...c,
    count: listings.filter((l) => l.category_id === c.id).length,
  }));

  return (
    <div>
      <h1 className="admin-page-title">Дашборд</h1>

      <div className="admin-stats">
        <div className="admin-stat-card">
          <span className="admin-stat-card__num">{loading ? '—' : listings.length}</span>
          <span className="admin-stat-card__label">Всего услуг</span>
        </div>
        <div className="admin-stat-card">
          <span className="admin-stat-card__num">{categories.length}</span>
          <span className="admin-stat-card__label">Категорий</span>
        </div>
      </div>

      <h2 className="admin-section-title">По категориям</h2>
      <div className="admin-table-wrap">
        <table className="admin-table">
          <thead>
            <tr><th>Категория</th><th>Услуг</th></tr>
          </thead>
          <tbody>
            {byCategory.map((c) => (
              <tr key={c.id}>
                <td>
                  <Link href={`/admin/services/${c.slug}`} className="admin-table__link">
                    {c.name_ru}
                  </Link>
                </td>
                <td>{loading ? '—' : c.count}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <Link href="/admin/categories/new" className="btn btn--gold" style={{ marginTop: 24, display: 'inline-flex' }}>
        + Добавить категорию
      </Link>
    </div>
  );
}
