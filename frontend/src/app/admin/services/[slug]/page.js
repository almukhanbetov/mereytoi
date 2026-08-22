'use client';

import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { useParams, useRouter } from 'next/navigation';
import { adminApi } from '@/lib/adminApi';
import { formatPrice } from '@/lib/format';
import { mediaUrl } from '@/lib/media';

export default function AdminCategoryServicesPage() {
  const { slug } = useParams();
  const router = useRouter();
  const [categories, setCategories] = useState([]);
  const [listings, setListings] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  function load() {
    setLoading(true);
    Promise.all([adminApi.categories(), adminApi.listings()])
      .then(([c, l]) => {
        setCategories(c.categories || []);
        setListings(l.listings || []);
      })
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }

  useEffect(load, []);

  const category = categories.find((c) => c.slug === slug);
  const items = useMemo(
    () => (category ? listings.filter((l) => l.category_id === category.id) : []),
    [listings, category]
  );

  async function handleDelete(id, name) {
    if (!window.confirm(`Удалить «${name}»?`)) return;
    try {
      await adminApi.deleteListing(id);
      setListings((prev) => prev.filter((l) => l.id !== id));
    } catch (err) {
      alert(err.message || 'Не удалось удалить');
    }
  }

  async function handleDeleteCategory() {
    if (!category) return;
    if (items.length > 0) {
      alert(`Нельзя удалить категорию «${category.name_ru}» — в ней есть услуги (${items.length}). Сначала удалите или перенесите их в другую категорию.`);
      return;
    }
    if (!window.confirm(`Удалить категорию «${category.name_ru}»?`)) return;
    try {
      await adminApi.deleteCategory(category.id);
      router.push('/admin');
    } catch (err) {
      alert(err.message || 'Не удалось удалить категорию');
    }
  }

  return (
    <div>
      <div className="admin-page-head">
        <h1 className="admin-page-title">{category ? category.name_ru : '…'}</h1>
        {category && (
          <div style={{ display: 'flex', gap: 10 }}>
            <Link href={`/admin/categories/edit/${category.id}`} className="btn btn--outline btn--sm">
              Изменить категорию
            </Link>
            <button type="button" className="btn btn--outline btn--sm" onClick={handleDeleteCategory}>
              Удалить категорию
            </button>
            <Link href={`/admin/services/new?category=${category.id}`} className="btn btn--gold btn--sm">
              + Добавить услугу
            </Link>
          </div>
        )}
      </div>

      {error && <p className="admin-login__error">{error}</p>}

      <div className="admin-table-wrap">
        <table className="admin-table">
          <thead>
            <tr>
              <th>Название</th>
              <th>Город</th>
              <th>Цена</th>
              <th>Рейтинг</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {loading && (
              <tr><td colSpan={5} className="admin-table__empty">Загрузка…</td></tr>
            )}
            {!loading && items.length === 0 && (
              <tr><td colSpan={5} className="admin-table__empty">Нет услуг в этой категории</td></tr>
            )}
            {items.map((l) => (
              <tr key={l.id}>
                <td className="admin-table__name-cell">
                  {l.image_urls?.[0]
                    ? <img src={mediaUrl(l.image_urls[0])} alt="" className="admin-table__thumb" />
                    : <span>{l.emoji}</span>}
                  {l.name_ru}
                </td>
                <td>{l.city || '—'}</td>
                <td>{l.price > 0 ? formatPrice(l.price) : 'По запросу'}</td>
                <td>{l.rating > 0 ? `★ ${l.rating.toFixed(1)}` : '—'}</td>
                <td className="admin-table__actions">
                  <Link href={`/admin/services/edit/${l.id}`} className="admin-table__link">Изменить</Link>
                  <button className="admin-table__link admin-table__link--danger" onClick={() => handleDelete(l.id, l.name_ru)}>
                    Удалить
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
