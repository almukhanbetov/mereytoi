'use client';

import { useEffect, useState } from 'react';
import { useParams } from 'next/navigation';
import { adminApi } from '@/lib/adminApi';
import ServiceForm from '@/components/admin/ServiceForm';

export default function EditServicePage() {
  const { id } = useParams();
  const [categories, setCategories] = useState([]);
  const [listing, setListing] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    Promise.all([adminApi.categories(), adminApi.listing(id)])
      .then(([c, l]) => {
        setCategories(c.categories || []);
        setListing(l.listing);
      })
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }, [id]);

  return (
    <div>
      <h1 className="admin-page-title">Редактировать услугу</h1>
      {error && <p className="admin-login__error">{error}</p>}
      {!loading && listing && <ServiceForm categories={categories} initial={listing} listingId={id} />}
    </div>
  );
}
