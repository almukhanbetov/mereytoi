'use client';

import ClientForm from '@/components/admin/ClientForm';

export default function NewClientPage() {
  return (
    <div>
      <h1 className="admin-page-title">Новый клиент</h1>
      <ClientForm />
    </div>
  );
}
