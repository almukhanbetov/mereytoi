'use client';

import { useEffect, useState } from 'react';
import { useParams } from 'next/navigation';
import { adminApi } from '@/lib/adminApi';
import ServiceForm from '@/components/admin/ServiceForm';
import RestaurantAdminTabs from '@/components/admin/RestaurantAdminTabs';
import { isRestaurantCategory } from '@/lib/restaurantCategory';

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

  // Restaurant/venue tabs (brief section 1) show only for that one
  // category — every other category's edit page keeps rendering the
  // exact same plain ServiceForm it always has (brief section 9 — "старый
  // service admin unchanged").
  const category = categories.find((c) => c.id === listing?.category_id);
  const isRestaurant = isRestaurantCategory(category);

  return (
    <div>
      <h1 className="admin-page-title">Редактировать услугу</h1>
      {error && <p className="admin-login__error">{error}</p>}
      {!loading && listing && (
        isRestaurant
          ? <RestaurantAdminTabs categories={categories} listing={listing} listingId={id} />
          : <ServiceForm categories={categories} initial={listing} listingId={id} />
      )}
    </div>
  );
}
