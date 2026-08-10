'use client';

import { useEffect, useState } from 'react';
import { useParams } from 'next/navigation';
import { adminApi } from '@/lib/adminApi';
import ClientForm from '@/components/admin/ClientForm';

export default function EditClientPage() {
  const { id } = useParams();
  const [client, setClient] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    adminApi.clients()
      .then((d) => {
        const found = (d.clients || []).find((c) => String(c.id) === String(id));
        if (!found) throw new Error('Клиент не найден');
        setClient(found);
      })
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }, [id]);

  return (
    <div>
      <h1 className="admin-page-title">Редактировать логотип</h1>
      {error && <p className="admin-login__error">{error}</p>}
      {!loading && client && <ClientForm initial={client} clientId={id} />}
    </div>
  );
}
