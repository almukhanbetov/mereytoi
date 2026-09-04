'use client';

import { Suspense, useState } from 'react';
import Link from 'next/link';
import { useRouter, useSearchParams } from 'next/navigation';
import { useAuth } from '@/context/AuthContext';
import { T } from '@/context/AppProviders';
import PasswordInput from '@/components/PasswordInput';

// useSearchParams() forces client-side rendering up to the nearest Suspense
// boundary during prerendering — without this wrapper the build fails with
// "useSearchParams() should be wrapped in a suspense boundary".
export default function LoginPage() {
  return (
    <Suspense>
      <LoginForm />
    </Suspense>
  );
}

function LoginForm() {
  const { login } = useAuth();
  const router = useRouter();
  const searchParams = useSearchParams();
  // Lets a flow like "open an invite link while logged out" return the user
  // to where they actually meant to go instead of always landing on the
  // generic /profile — defaults to the previous behavior when absent.
  const next = searchParams.get('next') || '/profile';
  const [identifier, setIdentifier] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit(e) {
    e.preventDefault();
    setError('');
    setSubmitting(true);
    try {
      await login(identifier, password);
      router.push(next);
    } catch (err) {
      setError(err.message || 'Не удалось войти');
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="auth-page">
      <form className="auth-card contacts__form" onSubmit={handleSubmit}>
        <Link href="/" className="logo">
          <span className="logo__mark">M</span>
          <span className="logo__text">MEREY<em>TOI</em></span>
        </Link>
        <p className="auth-card__title"><T ru="Вход в личный кабинет" kz="Жеке кабинетке кіру" /></p>

        <label>
          <span><T ru="Email или телефон" kz="Email немесе телефон" /></span>
          <input
            type="text"
            value={identifier}
            onChange={(e) => setIdentifier(e.target.value)}
            required
            placeholder="you@mereytoi.kz или +7 700 000 00 00"
          />
        </label>
        <label>
          <span><T ru="Пароль" kz="Құпия сөз" /></span>
          <PasswordInput value={password} onChange={(e) => setPassword(e.target.value)} required placeholder="••••••••" />
        </label>

        {error && <p className="auth-card__error">{error}</p>}

        <button type="submit" className="btn btn--gold btn--block" disabled={submitting}>
          {submitting ? <T ru="Входим…" kz="Кірілуде…" /> : <T ru="Войти" kz="Кіру" />}
        </button>

        <p className="auth-card__switch">
          <T ru="Ещё нет аккаунта?" kz="Аккаунтыңыз жоқ па?" />{' '}
          <Link href="/register"><T ru="Зарегистрироваться" kz="Тіркелу" /></Link>
        </p>
      </form>
    </div>
  );
}
