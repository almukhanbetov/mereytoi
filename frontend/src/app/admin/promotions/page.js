'use client';

import { useEffect, useState } from 'react';
import { adminApi } from '@/lib/adminApi';
import { formatPrice } from '@/lib/format';

const STATUS = { active: 'Активно', refunded: 'Возврат', revoked: 'Отозвано' };
const CHANNEL = { google: 'Google Play', apple: 'App Store', web: 'Сайт' };

function date(value) {
  return value ? new Date(value).toLocaleDateString('ru-RU') : '—';
}

function Ready({ ok, children }) {
  return (
    <li style={{ color: ok ? 'var(--text)' : 'var(--text-muted)' }}>
      {ok ? '✓' : '✗'} {children}
    </li>
  );
}

// Paid promotion — the only place its price is set. Store prices are set
// for the product in App Store Connect / Play Console; keep them in line.
export default function AdminPromotionsPage() {
  const [form, setForm] = useState(null);
  const [info, setInfo] = useState(null);
  const [list, setList] = useState([]);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');
  const [saving, setSaving] = useState(false);

  function apply(data) {
    const s = data.settings || {};
    setForm({
      enabled: !!s.enabled,
      price_kzt: s.price_kzt ? String(s.price_kzt) : '',
      google_product_id: s.google_product_id || '',
      apple_product_id: s.apple_product_id || '',
    });
    setInfo(data);
  }

  useEffect(() => {
    Promise.all([adminApi.promotionSettings(), adminApi.promotions()])
      .then(([settings, promos]) => {
        apply(settings);
        setList(promos.promotions || []);
      })
      .catch((err) => setError(err.message || 'Не удалось загрузить настройки'));
  }, []);

  async function handleSubmit(e) {
    e.preventDefault();
    setError('');
    setSuccess('');
    const price = Number(form.price_kzt || 0);
    if (!Number.isInteger(price) || price < 0) {
      setError('Цена — целое число тенге не меньше 0');
      return;
    }
    if (form.enabled && price === 0) {
      setError('Чтобы включить продажи, задайте цену');
      return;
    }
    setSaving(true);
    try {
      const data = await adminApi.updatePromotionSettings({
        enabled: form.enabled,
        price_kzt: price,
        google_product_id: form.google_product_id.trim(),
        apple_product_id: form.apple_product_id.trim(),
      });
      apply(data);
      setSuccess('Настройки сохранены');
    } catch (err) {
      setError(err.message || 'Не удалось сохранить');
    } finally {
      setSaving(false);
    }
  }

  const r = info?.readiness || {};
  return (
    <div>
      <h1 className="admin-page-title">Продвижение карточек</h1>
      {!form ? (
        <p>{error || 'Загрузка…'}</p>
      ) : (
        <>
          <p style={{ maxWidth: 640, color: 'var(--text-muted)' }}>
            Один пакет: {info?.duration_days || 7} дней, без автопродления. Реклама — вторая карточка
            выдачи, затем через {info?.layout?.every ?? 6} обычных (настраивается на сервере).
            Покупка в приложении идёт через Google Play и App Store по цене товара в их консолях.
          </p>
          <ul style={{ listStyle: 'none', padding: 0, margin: '16px 0', lineHeight: 1.8 }}>
            <Ready ok={r.feature_flag}>Флаг PROMOTIONS_ENABLED на сервере</Ready>
            <Ready ok={r.google_configured}>Google Play: сервисный аккаунт</Ready>
            <Ready ok={r.google_rtdn_token}>Google Play: токен уведомлений RTDN</Ready>
            <Ready ok={r.apple_configured}>App Store: сертификат Apple Root CA ({r.apple_environment || '—'})</Ready>
            <Ready ok={r.web_payment}>Оплата на сайте (провайдер не подключён)</Ready>
          </ul>

          <form className="contacts__form admin-form" onSubmit={handleSubmit} style={{ maxWidth: 480 }}>
            <label style={{ flexDirection: 'row', alignItems: 'center', gap: 10 }}>
              <input
                type="checkbox"
                checked={form.enabled}
                onChange={(e) => setForm((v) => ({ ...v, enabled: e.target.checked }))}
                style={{ width: 'auto' }}
              />
              <span>Продажи и показ рекламы включены</span>
            </label>
            <label>
              <span>Цена пакета, ₸</span>
              <input
                type="number"
                min="0"
                step="1"
                value={form.price_kzt}
                onChange={(e) => setForm((v) => ({ ...v, price_kzt: e.target.value }))}
              />
            </label>
            <label>
              <span>ID товара в Google Play</span>
              <input value={form.google_product_id} onChange={(e) => setForm((v) => ({ ...v, google_product_id: e.target.value }))} placeholder="promotion_7d" />
            </label>
            <label>
              <span>ID товара в App Store</span>
              <input value={form.apple_product_id} onChange={(e) => setForm((v) => ({ ...v, apple_product_id: e.target.value }))} placeholder="kz.mereytoi.promotion7d" />
            </label>
            {error && <p className="admin-login__error">{error}</p>}
            {success && <p className="form-success is-visible">{success}</p>}
            <button type="submit" className="btn btn--gold" disabled={saving}>
              {saving ? 'Сохраняем…' : 'Сохранить'}
            </button>
          </form>

          <h2 className="admin-section-title">Купленные продвижения</h2>
          {list.length === 0 ? (
            <p className="admin-table__empty">Пока нет</p>
          ) : (
            <div className="admin-table-wrap">
              <table className="admin-table">
                <thead>
                  <tr>
                    <th>Карточка</th>
                    <th>Канал</th>
                    <th>Период</th>
                    <th>Статус</th>
                    <th>Показы / переходы</th>
                    <th>Цена</th>
                  </tr>
                </thead>
                <tbody>
                  {list.map((row) => {
                    const p = row.promotion;
                    return (
                      <tr key={p.id}>
                        <td>{row.listing_name || `#${row.listing_id}`}</td>
                        <td>{CHANNEL[p.channel] || p.channel}</td>
                        <td>{date(p.starts_at)} — {date(p.ends_at)}</td>
                        <td>{p.running ? 'Идёт' : (STATUS[p.status] || p.status)}{row.revoke_reason ? ` (${row.revoke_reason})` : ''}</td>
                        <td>{p.stats.impressions} / {p.stats.clicks}</td>
                        <td>{row.price_kzt ? formatPrice(row.price_kzt) : '—'}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </>
      )}
    </div>
  );
}
