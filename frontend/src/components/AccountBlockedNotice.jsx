'use client';

import { useState } from 'react';
import { T } from '@/context/AppProviders';
import { useAuth } from '@/context/AuthContext';

function formatDateTime(v) {
  if (!v) return '';
  return new Date(v).toLocaleString('ru-RU', {
    day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit',
  });
}

// «Аккаунт заблокирован» — shown on sign-in, when a stored session turns
// out to be blocked, and after a recovery on a blocked account (then with
// the new backup code: the old one is spent and must not be lost).
export default function AccountBlockedNotice() {
  const { blockInfo, clearBlockInfo } = useAuth();
  const [copied, setCopied] = useState(false);
  if (!blockInfo) return null;
  const until = blockInfo.blocked_until;
  const code = blockInfo.password_reset ? blockInfo.recovery_code : '';
  return (
    <div className="report-overlay" role="presentation">
      <div className="report-dialog" role="alertdialog" aria-modal="true" aria-labelledby="blocked-title" data-testid="account-blocked">
        <h3 id="blocked-title" className="report-dialog__title">
          <T ru="Аккаунт заблокирован" kz="Аккаунт бұғатталған" en="Your account is blocked" />
        </h3>
        <div className="report-summary">
          <div>
            <T ru="Срок" kz="Мерзімі" en="Term" />:{' '}
            <b className={until ? '' : 'blocked-indefinite'}>
              {until
                ? <T ru={`до ${formatDateTime(until)}`} kz={`${formatDateTime(until)} дейін`} en={`until ${formatDateTime(until)}`} />
                : <T ru="бессрочно" kz="мерзімсіз" en="indefinite" />}
            </b>
          </div>
          {blockInfo.reason && (
            <div><T ru="Причина" kz="Себебі" en="Reason" />: <b>{blockInfo.reason}</b></div>
          )}
        </div>
        <p className="report-dialog__note">
          <T ru="Пока действует блокировка, войти в MEREYTOI нельзя. Если вы считаете это ошибкой, свяжитесь с поддержкой." kz="Бұғаттау әрекет етіп тұрғанда MEREYTOI-ға кіру мүмкін емес. Егер бұл қате деп ойласаңыз, қолдау қызметіне хабарласыңыз." en="While the block is in force you can't sign in to MEREYTOI. If you think this is a mistake, contact support." />
        </p>
        {code && (
          <div className="report-summary">
            <div>
              <T ru="Пароль изменён. Сохраните новый резервный код — старый больше не действует." kz="Құпиясөз өзгертілді. Жаңа резервтік кодты сақтаңыз — ескісі енді жарамсыз." en="Your password was changed. Save your new backup code — the old one no longer works." />
            </div>
            <div className="blocked-code" data-testid="blocked-code">{code}</div>
            <button
              type="button"
              className="btn btn--outline btn--sm"
              onClick={() => navigator.clipboard?.writeText(code).then(() => setCopied(true)).catch(() => {})}
            >
              {copied ? <T ru="Скопировано" kz="Көшірілді" en="Copied" /> : <T ru="Скопировать код" kz="Кодты көшіру" en="Copy code" />}
            </button>
          </div>
        )}
        <div className="report-dialog__actions">
          <button type="button" className="btn btn--gold" onClick={clearBlockInfo}>
            <T ru="Понятно" kz="Түсінікті" en="Got it" />
          </button>
        </div>
      </div>
    </div>
  );
}
