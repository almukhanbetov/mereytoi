'use client';

import { useEffect, useState } from 'react';
import { useSearchParams } from 'next/navigation';
import { adminApi } from '@/lib/adminApi';
import ServiceForm from '@/components/admin/ServiceForm';

export default function NewServicePage() {
  const searchParams = useSearchParams();
  const presetCategory = searchParams.get('category') || '';
  const [categories, setCategories] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    adminApi.categories().then((d) => setCategories(d.categories || [])).finally(() => setLoading(false));
  }, []);

  return (
    <div>
      <h1 className="admin-page-title">Новая услуга</h1>
      {!loading && <ServiceForm categories={categories} initial={{ category_id: presetCategory }} />}
    </div>
  );
}
