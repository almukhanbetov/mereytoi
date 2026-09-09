'use client';

import { useState } from 'react';
import { T } from '@/context/AppProviders';
import { useAuth } from '@/context/AuthContext';
import { authApi } from '@/lib/authApi';

/** Brief section 4's optional entry point into Telegram linking — a small,
 * self-contained card so profile/page.js only needs one import + one
 * render line. Telegram itself only becomes a usable claim-delivery
 * channel for a user once this flow completes (see
 * claimdelivery.Service.pickChannel on the backend); nothing here is
 * required for the workspace/claim flow to work. */
export default function TelegramConnectCard() {
  const { telegramLinked, refreshMe } = useAuth();
  const [state, setState] = useState('idle'); // idle | opening | waiting | unavailable

  async function handleConnect() {
    setState('opening');
    try {
      const { configured, link_url: linkUrl } = await authApi.telegramLinkToken();
      if (!configured) {
        setState('unavailable');
        return;
      }
      window.open(linkUrl, '_blank', 'noopener,noreferrer');
      setState('waiting');
    } catch {
      setState('unavailable');
    }
  }

  async function handleCheckAgain() {
    await refreshMe();
  }

  return (
    <div className="ws-event-card" style={{ padding: 20, marginTop: 18 }}>
      <h3 style={{ margin: '0 0 6px', fontSize: 15 }}>
        <T ru="Уведомления в Telegram" kz="Telegram хабарламалары" />
      </h3>

      {telegramLinked ? (
        <p className="booking-workspace-cta__text" style={{ margin: 0 }}>
          ✅ <T ru="Telegram подключён." kz="Telegram қосылды." />
        </p>
      ) : (
        <>
          <p className="booking-workspace-cta__text" style={{ margin: '0 0 12px' }}>
            <T
              ru="Получать ссылки и уведомления в Telegram."
              kz="Telegram арқылы сілтемелер мен хабарламалар алу."
            />
          </p>

          {state === 'unavailable' ? (
            <p className="booking-workspace-cta__text booking-workspace-cta__text--muted" style={{ margin: 0 }}>
              <T ru="Telegram пока недоступен." kz="Telegram әзірге қолжетімсіз." />
            </p>
          ) : state === 'waiting' ? (
            <>
              <p className="booking-workspace-cta__text booking-workspace-cta__text--muted" style={{ margin: '0 0 8px' }}>
                <T
                  ru="Откройте Telegram и нажмите «Начать» в чате с ботом, затем вернитесь сюда."
                  kz="Telegram-ды ашып, бот чатында «Бастау» батырмасын басыңыз, содан кейін осында қайтыңыз."
                />
              </p>
              <button type="button" className="btn btn--outline btn--sm" onClick={handleCheckAgain}>
                <T ru="Я подключил, проверить" kz="Қосылды, тексеру" />
              </button>
            </>
          ) : (
            <button type="button" className="btn btn--outline btn--sm" onClick={handleConnect} disabled={state === 'opening'}>
              <T ru="Подключить Telegram" kz="Telegram қосу" />
            </button>
          )}
        </>
      )}
    </div>
  );
}
