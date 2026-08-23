'use client';

import { useEffect, useState } from 'react';
import { adminApi } from '@/lib/adminApi';

const FIELDS = [
  { key: 'events_count', label: 'Проведено тоев' },
  { key: 'happy_guests_count', label: 'Довольных гостей' },
  { key: 'years_experience', label: 'Лет опыта' },
  { key: 'cities_count', label: 'Городов' },
];

export default function AdminStatisticsPage() {
  const [values, setValues] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    adminApi.siteStatistics()
      .then(setValues)
      .catch((err) => setError(err.message || 'Не удалось загрузить статистику'))
      .finally(() => setLoading(false));
  }, []);

  function handleChange(key, raw) {
    setSuccess('');
    setValues((v) => ({ ...v, [key]: raw }));
  }

  async function handleSubmit(e) {
    e.preventDefault();
    setError('');
    setSuccess('');

    const payload = {};
    for (const { key } of FIELDS) {
      const num = Number(values[key]);
      if (values[key] === '' || !Number.isFinite(num) || num < 0) {
        setError('Все значения должны быть целыми числами не меньше 0');
        return;
      }
      payload[key] = Math.trunc(num);
    }

    setSubmitting(true);
    try {
      const updated = await adminApi.updateSiteStatistics(payload);
      setValues(updated);
      setSuccess('Статистика сохранена');
    } catch (err) {
      setError(err.message || 'Не удалось сохранить статистику');
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div>
      <h1 className="admin-page-title">Статистика сайта</h1>

      {loading ? (
        <p>Загрузка…</p>
      ) : (
        <form className="contacts__form admin-form" onSubmit={handleSubmit} style={{ maxWidth: 480 }}>
          {FIELDS.map(({ key, label }) => (
            <label key={key}>
              <span>{label}</span>
              <input
                type="number"
                min="0"
                step="1"
                value={values?.[key] ?? ''}
                onChange={(e) => handleChange(key, e.target.value)}
              />
            </label>
          ))}

          {error && <p className="admin-login__error">{error}</p>}
          {success && <p className="form-success is-visible">{success}</p>}

          <button type="submit" className="btn btn--gold" disabled={submitting}>
            {submitting ? 'Сохраняем…' : 'Сохранить'}
          </button>
        </form>
      )}
    </div>
  );
}
