'use client';

import { Suspense, useState } from 'react';
import Link from 'next/link';
import { useRouter, useSearchParams } from 'next/navigation';
import { useAuth } from '@/context/AuthContext';
import { T } from '@/context/AppProviders';
import PasswordInput from '@/components/PasswordInput';
import RecoveryCodePanel from '@/components/auth/RecoveryCodePanel';

// See login/page.js for why this needs a Suspense boundary.
export default function RegisterPage() {
  return (
    <Suspense>
      <RegisterForm />
    </Suspense>
  );
}

function RegisterForm() {
  const { register } = useAuth();
  const router = useRouter();
  const searchParams = useSearchParams();
  const next = searchParams.get('next') || '/profile';
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [phone, setPhone] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [submitting, setSubmitting] = useState(false);
  // The backup code from the registration response — shown once, then the
  // user continues; never persisted.
  const [recoveryCode, setRecoveryCode] = useState('');

  async function handleSubmit(e) {
    e.preventDefault();
    setError('');
    setSubmitting(true);
    try {
      const { recoveryCode: code } = await register(name, email, phone, password);
      if (code) {
        setRecoveryCode(code);
      } else {
        router.push(next);
      }
    } catch (err) {
      setError(err.message === 'weak_password' ? 'Пароль должен быть не короче 8 символов' : err.message || 'Не удалось зарегистрироваться');
    } finally {
      setSubmitting(false);
    }
  }

  if (recoveryCode) {
    return (
      <div className="auth-page">
        <div className="auth-card contacts__form">
          <p className="auth-card__title"><T ru="Аккаунт создан" kz="Аккаунт жасалды" en="Account created" /></p>
          <RecoveryCodePanel
            code={recoveryCode}
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
        <p className="auth-card__title"><T ru="Создать аккаунт" kz="Аккаунт жасау" /></p>

        <label>
          <span><T ru="Ваше имя" kz="Атыңыз" /></span>
          <input type="text" value={name} onChange={(e) => setName(e.target.value)} required placeholder="Aidos" />
        </label>
        <label>
          <span>Email</span>
          <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} required placeholder="you@mereytoi.kz" />
        </label>
        <label>
          <span><T ru="Телефон" kz="Телефон" /></span>
          <input type="tel" value={phone} onChange={(e) => setPhone(e.target.value)} placeholder="+7 700 000 00 00" />
        </label>
        <label>
          <span><T ru="Пароль" kz="Құпия сөз" /></span>
          <PasswordInput value={password} onChange={(e) => setPassword(e.target.value)} required minLength={8} autoComplete="new-password" placeholder="Минимум 8 символов" />
        </label>

        {error && <p className="auth-card__error">{error}</p>}

        <button type="submit" className="btn btn--gold btn--block" disabled={submitting}>
          {submitting ? <T ru="Создаём…" kz="Жасалуда…" /> : <T ru="Зарегистрироваться" kz="Тіркелу" />}
        </button>

        <p className="auth-card__switch">
          <T ru="Уже есть аккаунт?" kz="Аккаунтыңыз бар ма?" />{' '}
          <Link href={searchParams.get('next') ? `/login?next=${encodeURIComponent(next)}` : '/login'}><T ru="Войти" kz="Кіру" /></Link>
        </p>
      </form>
    </div>
  );
}
