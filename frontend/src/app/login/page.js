'use client';

import { useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/context/AuthContext';
import { T } from '@/context/AppProviders';
import PasswordInput from '@/components/PasswordInput';

export default function LoginPage() {
  const { login } = useAuth();
  const router = useRouter();
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
      router.push('/profile');
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
