'use client';

import { useEffect, useState } from 'react';
import { T, useLang } from '@/context/AppProviders';
import { authApi } from '@/lib/authApi';
import PasswordInput from '@/components/PasswordInput';
import RecoveryCodePanel from '@/components/auth/RecoveryCodePanel';

/** Профиль → «Резервный код восстановления»: shows whether the account has
 * a backup code (from /api/auth/me — never the code itself), creates one
 * for accounts that have none, or replaces it after an explicit
 * confirmation (the old code stops working at once). Both need the current
 * password; the new code is shown once. Rendered inside the profile <form>,
 * so it has no form of its own: buttons are type="button" and Enter in its
 * password field is handled here. */
export default function RecoveryCodeCard() {
  const { lang } = useLang();
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [code, setCode] = useState('');
  // 'loading' | 'missing' | 'present' | 'unknown'
  const [status, setStatus] = useState('loading');
  const [confirming, setConfirming] = useState(false);

  useEffect(() => {
    let cancelled = false;
    authApi
      .me()
      .then((data) => {
        if (!cancelled) setStatus(data.has_recovery_code ? 'present' : 'missing');
      })
      .catch(() => {
        if (!cancelled) setStatus('unknown');
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const replacing = status !== 'missing';

  const pick = (ru, kz, en) => (lang === 'kz' ? kz : lang === 'en' ? en : ru);

  function handlePrimary() {
    if (!password) return;
    if (replacing && !confirming) {
      setConfirming(true);
      return;
    }
    handleCreate();
  }

  async function handleCreate() {
    if (!password) return;
    setConfirming(false);
    setBusy(true);
    setError('');
    try {
      const { recovery_code: recoveryCode } = await authApi.replaceRecoveryCode(password);
      setPassword('');
      setStatus('present');
      setCode(recoveryCode);
    } catch (err) {
      setError(
        err.message === 'wrong_current_password'
          ? pick('Неверный текущий пароль', 'Ағымдағы құпиясөз қате', 'Wrong current password')
          : err.message === 'too_many_attempts'
            ? pick('Слишком много попыток. Попробуйте снова через 15 минут.', 'Әрекеттер тым көп. 15 минуттан кейін қайталап көріңіз.', 'Too many attempts. Try again in 15 minutes.')
            : pick('Не удалось создать код', 'Код жасау мүмкін болмады', "Couldn't create the code"),
      );
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="ws-event-card" style={{ padding: 20, marginTop: 18 }}>
      <h3 style={{ margin: '0 0 6px', fontSize: 15 }}>
        <T ru="Резервный код восстановления" kz="Қалпына келтіру резервтік коды" en="Recovery backup code" />
      </h3>
      {code ? (
        <RecoveryCodePanel code={code} onDone={() => setCode('')} />
      ) : (
        <>
          <p className="booking-workspace-cta__text" style={{ margin: '0 0 12px' }}>
            <T
              ru="С резервным кодом можно сменить забытый пароль без SMS и WhatsApp. Код показывается только один раз, сразу после создания, — сохраните его в надёжном месте."
              kz="Резервтік кодпен ұмытылған құпиясөзді SMS пен WhatsApp-сыз өзгертуге болады. Код тек бір рет, жасалғаннан кейін бірден көрсетіледі — оны сенімді жерде сақтаңыз."
              en="A backup code lets you reset a forgotten password without SMS or WhatsApp. It is shown only once, right after it is created — keep it somewhere safe."
            />
          </p>
          <p className="recovery-code__status" data-status={status}>
            {status === 'loading' && <T ru="Проверяем…" kz="Тексерілуде…" en="Checking…" />}
            {status === 'missing' && (
              <T
                ru="⚠️ Резервный код ещё не создан. Без него забытый пароль можно восстановить только через менеджера."
                kz="⚠️ Резервтік код әлі жасалмаған. Онсыз ұмытылған құпиясөзді тек менеджер арқылы қалпына келтіруге болады."
                en="⚠️ No backup code yet. Without one, a forgotten password can only be restored through a manager."
              />
            )}
            {status === 'present' && (
              <T ru="✅ Резервный код создан. Посмотреть его снова нельзя." kz="✅ Резервтік код жасалған. Оны қайта көру мүмкін емес." en="✅ A backup code exists. It can't be shown again." />
            )}
            {status === 'unknown' && (
              <T ru="Новый код заменит прежний, если он был." kz="Жаңа код бұрынғысын ауыстырады, егер ол болса." en="A new code replaces the previous one, if any." />
            )}
          </p>
          <label>
            <span><T ru="Текущий пароль" kz="Ағымдағы құпиясөз" en="Current password" /></span>
            <PasswordInput
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              autoComplete="current-password"
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  e.preventDefault();
                  handlePrimary();
                }
              }}
            />
          </label>
          {error && <p className="auth-card__error" style={{ textAlign: 'left', marginTop: 8 }}>{error}</p>}
          {confirming ? (
            <div className="recovery-code__confirm-replace" role="alertdialog">
              <p className="booking-workspace-cta__text" style={{ margin: '12px 0 8px' }}>
                <T
                  ru="Заменить резервный код? Текущий код сразу перестанет работать."
                  kz="Резервтік кодты ауыстыру керек пе? Ағымдағы код бірден жарамсыз болады."
                  en="Replace the backup code? The current code will stop working at once."
                />
              </p>
              <button type="button" className="btn btn--gold btn--sm" onClick={handleCreate} disabled={busy}>
                <T ru="Заменить" kz="Ауыстыру" en="Replace" />
              </button>{' '}
              <button type="button" className="btn btn--outline btn--sm" onClick={() => setConfirming(false)} disabled={busy}>
                <T ru="Отмена" kz="Болдырмау" en="Cancel" />
              </button>
            </div>
          ) : (
            <button type="button" className="btn btn--outline btn--sm" style={{ marginTop: 12 }} onClick={handlePrimary} disabled={busy || !password || status === 'loading'}>
              {busy ? (
                <T ru="Создаём…" kz="Жасалуда…" en="Creating…" />
              ) : replacing ? (
                <T ru="Заменить код" kz="Кодты ауыстыру" en="Replace the code" />
              ) : (
                <T ru="Создать резервный код" kz="Резервтік код жасау" en="Create a backup code" />
              )}
            </button>
          )}
        </>
      )}
    </div>
  );
}
