'use client';

import { Suspense, useState } from 'react';
import Link from 'next/link';
import { useRouter, useSearchParams } from 'next/navigation';
import { useAuth } from '@/context/AuthContext';
import { T, useLang } from '@/context/AppProviders';
import PasswordInput from '@/components/PasswordInput';
import RecoveryCodePanel from '@/components/auth/RecoveryCodePanel';

const MIN_PASSWORD = 8;

// See login/page.js for why this needs a Suspense boundary.
export default function RecoverPage() {
  return (
    <Suspense>
      <RecoverForm />
    </Suspense>
  );
}

function errorText(code, lang) {
  const pick = (ru, kz, en) => (lang === 'kz' ? kz : lang === 'en' ? en : ru);
  switch (code) {
    case 'invalid_recovery_code':
      return pick(
        'Неверный код или email/телефон. Проверьте данные.',
        'Код немесе email/телефон қате. Деректерді тексеріңіз.',
        'Wrong code or email/phone. Please check and try again.',
      );
    case 'too_many_attempts':
      return pick(
        'Слишком много попыток. Попробуйте снова через 15 минут.',
        'Әрекеттер тым көп. 15 минуттан кейін қайталап көріңіз.',
        'Too many attempts. Try again in 15 minutes.',
      );
    case 'weak_password':
      return pick(
        `Пароль должен быть не короче ${MIN_PASSWORD} символов`,
        `Құпиясөз кемінде ${MIN_PASSWORD} таңбадан тұруы керек`,
        `Password must be at least ${MIN_PASSWORD} characters`,
      );
    case 'password_too_long':
      return pick('Пароль слишком длинный', 'Құпиясөз тым ұзын', 'Password is too long');
    default:
      return pick('Не удалось восстановить пароль', 'Құпиясөзді қалпына келтіру мүмкін болмады', "Couldn't recover the password");
  }
}

/** «Забыли пароль?» — recovery with the one-time backup code: email/phone,
 * the code, a new password. Needs no SMS/WhatsApp. On success the backend
 * revokes every older session, signs this one in and returns a new code,
 * shown once before continuing. */
function RecoverForm() {
  const { recover } = useAuth();
  const { lang } = useLang();
  const router = useRouter();
  const searchParams = useSearchParams();
  const next = searchParams.get('next') || '/profile';
  const [login, setLogin] = useState('');
  const [code, setCode] = useState('');
  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [error, setError] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [newCode, setNewCode] = useState('');

  async function handleSubmit(e) {
    e.preventDefault();
    setError('');
    if (password.length < MIN_PASSWORD) {
      setError(errorText('weak_password', lang));
      return;
    }
    if (password !== confirm) {
      setError(lang === 'kz' ? 'Құпиясөздер сәйкес емес' : lang === 'en' ? "Passwords don't match" : 'Пароли не совпадают');
      return;
    }
    setSubmitting(true);
    try {
      const { recoveryCode } = await recover(login, code, password);
      setCode('');
      setPassword('');
      setConfirm('');
      if (recoveryCode) {
        setNewCode(recoveryCode);
      } else {
        router.push(next);
      }
    } catch (err) {
      setError(errorText(err.message, lang));
    } finally {
      setSubmitting(false);
    }
  }

  if (newCode) {
    return (
      <div className="auth-page">
        <div className="auth-card contacts__form">
          <p className="auth-card__title">
            <T ru="Пароль изменён. Это ваш новый резервный код — прежний больше не действует." kz="Құпиясөз өзгертілді. Бұл сіздің жаңа резервтік кодыңыз — бұрынғысы енді жарамсыз." en="Password changed. This is your new backup code — the previous one no longer works." />
          </p>
          <RecoveryCodePanel
            code={newCode}
            onDone={() => router.push(next)}
            doneLabel={<T ru="Продолжить" kz="Жалғастыру" en="Continue" />}
          />
        </div>
      </div>
    );
  }

  return (
    <div className="auth-page">
      <form className="auth-card contacts__form" onSubmit={handleSubmit}>
        <Link href="/" className="logo">
          <span className="logo__mark">M</span>
          <span className="logo__text">MEREY<em>TOI</em></span>
        </Link>
        <p className="auth-card__title">
          <T ru="Восстановление пароля по резервному коду" kz="Резервтік код арқылы құпиясөзді қалпына келтіру" en="Recover your password with a backup code" />
        </p>

        <label>
          <span><T ru="Email или телефон" kz="Email немесе телефон" en="Email or phone" /></span>
          <input type="text" value={login} onChange={(e) => setLogin(e.target.value)} required autoComplete="username" placeholder="you@mereytoi.kz или +7 700 000 00 00" />
        </label>
        <label>
          <span><T ru="Резервный код" kz="Резервтік код" en="Backup code" /></span>
          <input
            type="text"
            value={code}
            onChange={(e) => setCode(e.target.value)}
            required
            autoComplete="off"
            autoCapitalize="characters"
            spellCheck={false}
            placeholder="XXXX-XXXX-XXXX-…"
          />
        </label>
        <label>
          <span><T ru="Новый пароль" kz="Жаңа құпиясөз" en="New password" /></span>
          <PasswordInput value={password} onChange={(e) => setPassword(e.target.value)} required minLength={MIN_PASSWORD} autoComplete="new-password" />
        </label>
        <label>
          <span><T ru="Повторите пароль" kz="Құпиясөзді қайталаңыз" en="Repeat password" /></span>
          <PasswordInput value={confirm} onChange={(e) => setConfirm(e.target.value)} required minLength={MIN_PASSWORD} autoComplete="new-password" />
        </label>

        {error && <p className="auth-card__error">{error}</p>}

        <button type="submit" className="btn btn--gold btn--block" disabled={submitting}>
          {submitting ? <T ru="Меняем…" kz="Өзгертілуде…" en="Saving…" /> : <T ru="Сменить пароль" kz="Құпиясөзді өзгерту" en="Change password" />}
        </button>

        <p className="auth-card__hint">
          <T
            ru="Нет кода? Если вы помните пароль, войдите и создайте новый код в личном кабинете. Если утеряны и пароль, и код — напишите менеджеру MEREYTOI."
            kz="Код жоқ па? Құпиясөзді есіңізде болса, кіріп, жеке кабинетте жаңа код жасаңыз. Құпиясөз де, код та жоғалса — MEREYTOI менеджеріне жазыңыз."
            en="No code? If you remember your password, sign in and create a new code in your account. If you lost both the password and the code, contact a MEREYTOI manager."
          />
        </p>

        <p className="auth-card__switch">
          <Link href={searchParams.get('next') ? `/login?next=${encodeURIComponent(next)}` : '/login'}>
            <T ru="Вернуться ко входу" kz="Кіруге оралу" en="Back to sign in" />
          </Link>
        </p>
      </form>
    </div>
  );
}
