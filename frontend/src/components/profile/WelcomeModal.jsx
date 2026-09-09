'use client';

import { T } from '@/context/AppProviders';
import WsModal from '@/components/profile/WsModal';

const CAPABILITIES = [
  { icon: '🤝', ru: 'Пригласить близких', kz: 'Жақындарыңызды шақыру' },
  { icon: '🎯', ru: 'Добавить услуги', kz: 'Қызметтер қосу' },
  { icon: '💬', ru: 'Обсудить варианты', kz: 'Нұсқаларды талқылау' },
  { icon: '💰', ru: 'Контролировать бюджет', kz: 'Бюджетті бақылау' },
  { icon: '📨', ru: 'Отправить итоговый выбор', kz: 'Соңғы таңдауды жіберу' },
];

/** Shown once, right after a first-ever claim (see /claim/[token]/page.js
 * and EventWorkspaceShell.jsx's own localStorage-flag gate) — a compact
 * capabilities list, not a multi-step wizard, matching the brief's own
 * "не делать длинный wizard". Reuses the existing WsModal shell rather
 * than a bespoke overlay. */
export default function WelcomeModal({ onClose }) {
  return (
    <WsModal title={<T ru="Добро пожаловать в «Мой той»" kz="«Менің тойым»-ға қош келдіңіз" en="Welcome to «Мой той»" />} onClose={onClose}>
      <p className="ws-empty__text" style={{ textAlign: 'left', marginBottom: 18 }}>
        <T
          ru="Это ваше пространство для совместной организации мероприятия."
          kz="Бұл — іс-шараны бірге ұйымдастыруға арналған кеңістігіңіз."
          en="This is your space for planning the event together."
        />
      </p>

      <ul style={{ listStyle: 'none', margin: '0 0 22px', padding: 0, display: 'flex', flexDirection: 'column', gap: 10 }}>
        {CAPABILITIES.map((c) => (
          <li key={c.ru} style={{ display: 'flex', alignItems: 'center', gap: 10, fontSize: 14 }}>
            <span style={{ fontSize: 18 }}>{c.icon}</span>
            <T ru={c.ru} kz={c.kz} />
          </li>
        ))}
      </ul>

      <button type="button" className="btn btn--gold btn--block" onClick={onClose}>
        <T ru="Начать" kz="Бастау" en="Get started" />
      </button>
      <button type="button" className="manager-widget__back" style={{ display: 'block', margin: '12px auto 0' }} onClick={onClose}>
        <T ru="Позже" kz="Кейінірек" en="Later" />
      </button>
    </WsModal>
  );
}
