'use client';

import { useEffect, useState } from 'react';
import { T, useLang } from '@/context/AppProviders';
import { fetchPromotionStatus } from '@/lib/promotionApi';

function date(value) {
  return value ? new Date(value).toLocaleDateString('ru-RU') : '';
}

function Stats({ stats }) {
  const items = [
    [<T key="i" ru="Показы" kz="Көрсетілім" />, stats.impressions],
    [<T key="c" ru="Переходы" kz="Өтулер" />, stats.clicks],
    [<T key="ch" ru="Чаты" kz="Чаттар" />, stats.chats],
    [<T key="ca" ru="Звонки" kz="Қоңыраулар" />, stats.calls],
    ['WhatsApp', stats.whatsapp],
  ];
  return (
    <>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: '12px 28px', margin: '12px 0' }}>
        {items.map(([label, value], i) => (
          <div key={i}>
            <div style={{ fontSize: 20, fontWeight: 700 }}>{(value || 0).toLocaleString('ru-RU')}</div>
            <div style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>{label}</div>
          </div>
        ))}
      </div>
      <p style={{ fontSize: 12.5, color: 'var(--text-muted)', margin: 0 }}>
        <T
          ru="Чаты, звонки и WhatsApp — это нажатия из рекламы, а не подтверждённые заказы."
          kz="Чаттар, қоңыраулар мен WhatsApp — жарнамадан жасалған басулар, расталған тапсырыстар емес."
        />
      </p>
    </>
  );
}

const BLOCKED = {
  not_owner: <T ru="Оплатить продвижение может только владелец карточки." kz="Жарнаманы тек карточка иесі төлей алады." />,
  listing_hidden: <T ru="Карточка скрыта. Опубликуйте её, чтобы продвигать." kz="Карточка жасырын. Жарнамалау үшін оны жариялаңыз." />,
  provider_not_active: <T ru="Профиль услугодателя не активен, продвижение недоступно." kz="Қызмет көрсетуші профилі белсенді емес, жарнама қолжетімсіз." />,
};

// «Продвигать» on the site: the package terms, price, status, end date and
// statistics. Paying happens in the MEREYTOI app (Google Play / App Store);
// no web payment provider is connected yet, so the site never takes money.
export default function PromotionPanel({ listing, onClose }) {
  const { lang } = useLang();
  const [status, setStatus] = useState(null);
  const [error, setError] = useState('');

  useEffect(() => {
    fetchPromotionStatus(listing.id)
      .then(setStatus)
      .catch((err) => setError(err.message || 'error'));
  }, [listing.id]);

  const name = lang === 'kz' ? listing.name_kz : listing.name_ru;
  const pkg = status?.package;
  const running = status?.running;
  const past = (status?.history || []).filter((p) => !p.running);

  return (
    <div className="provider-form-card" style={{ margin: '20px 0', padding: 24 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, alignItems: 'baseline', flexWrap: 'wrap' }}>
        <h3 className="admin-section-title" style={{ margin: 0 }}>
          <T ru="Продвижение" kz="Жарнама" />: {name}
        </h3>
        <button type="button" className="admin-table__link" onClick={onClose}>
          <T ru="Закрыть" kz="Жабу" />
        </button>
      </div>

      {error && <p className="admin-login__error"><T ru="Не удалось загрузить данные о продвижении." kz="Жарнама деректерін жүктеу мүмкін болмады." /></p>}
      {!status && !error && <p><T ru="Загрузка…" kz="Жүктелуде…" /></p>}

      {status && (
        <>
          {running && (
            <div style={{ marginTop: 16 }}>
              <strong>
                <T ru={`Продвигается до ${date(running.ends_at)}`} kz={`${date(running.ends_at)} дейін жарнамалануда`} />
              </strong>
              <Stats stats={running.stats} />
            </div>
          )}

          <div style={{ marginTop: 16 }}>
            <p style={{ margin: '0 0 6px', fontWeight: 700 }}>
              <T ru={`Пакет «${pkg.duration_days} дней»`} kz={`«${pkg.duration_days} күн» пакеті`} />
            </p>
            {/* The real charge is the store product's price; the admin
                figure is never shown as the price to pay. */}
            <p style={{ margin: '0 0 6px', fontSize: 14, color: 'var(--text-muted)' }}>
              <T
                ru="Цену и валюту покажет Google Play или App Store перед оплатой в приложении."
                kz="Бағасы мен валютасын қосымшада төлер алдында Google Play немесе App Store көрсетеді."
              />
            </p>
            <ul style={{ margin: 0, paddingLeft: 18, lineHeight: 1.7, fontSize: 14 }}>
              <li><T ru={`${pkg.duration_days} дней с момента подтверждения оплаты`} kz={`Төлем расталған сәттен бастап ${pkg.duration_days} күн`} /></li>
              <li><T ru="Без автопродления" kz="Автоматты ұзартусыз" /></li>
              <li><T ru="Карточка показывается с пометкой «Реклама» только тем, кто ищет в её городе и категории" kz="Карточка «Жарнама» белгісімен тек оның қаласы мен санатында іздегендерге көрсетіледі" /></li>
              <li><T ru="Рейтинг, отзывы и значки не меняются" kz="Рейтинг, пікірлер мен белгілер өзгермейді" /></li>
            </ul>
          </div>

          {!running && (
            <p style={{ marginTop: 16, fontSize: 14 }}>
              {status.can_purchase
                ? <T ru="Оплата на сайте пока недоступна. Купить продвижение можно в приложении MEREYTOI для Android или iPhone: «Мои услуги» → «Продвигать»." kz="Сайтта төлеу әзірге қолжетімсіз. Жарнаманы Android немесе iPhone-ға арналған MEREYTOI қосымшасында сатып алуға болады: «Менің қызметтерім» → «Жарнамалау»." />
                : (BLOCKED[status.blocked_reason] || <T ru="Продвижение пока недоступно." kz="Жарнама әзірге қолжетімсіз." />)}
            </p>
          )}

          {past.length > 0 && (
            <div style={{ marginTop: 20 }}>
              <p style={{ fontWeight: 700, margin: '0 0 6px' }}><T ru="История" kz="Тарих" /></p>
              {past.map((p) => (
                <div key={p.id} style={{ marginBottom: 14 }}>
                  <div style={{ fontSize: 14 }}>
                    {date(p.starts_at)} — {date(p.ends_at)} ·{' '}
                    {p.status === 'active' ? <T ru="Завершено" kz="Аяқталды" /> : <T ru="Возврат оплаты" kz="Төлем қайтарылды" />}
                  </div>
                  <Stats stats={p.stats} />
                </div>
              ))}
            </div>
          )}
        </>
      )}
    </div>
  );
}
