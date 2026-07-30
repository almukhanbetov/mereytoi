'use client';

import { useState } from 'react';
import { useAdminAuth } from '@/context/AdminAuthContext';
import PasswordInput from '@/components/PasswordInput';

export default function AdminLoginPage() {
  const { login } = useAdminAuth();
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
    } catch (err) {
      setError(err.message || 'Не удалось войти');
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="admin-login">
      <form className="admin-login__card contacts__form" onSubmit={handleSubmit}>
        <div className="logo admin-login__logo">
          <span className="logo__mark">M</span>
          <span className="logo__text">MEREY<em>TOI</em></span>
        </div>
        <p className="admin-login__title">Вход в админ-панель</p>

        <label>
          <span>Email или телефон</span>
          <input
            type="text"
            value={identifier}
            onChange={(e) => setIdentifier(e.target.value)}
            required
            placeholder="admin@mereytoi.kz или +7 700 000 00 00"
          />
        </label>
        <label>
          <span>Пароль</span>
          <PasswordInput value={password} onChange={(e) => setPassword(e.target.value)} required placeholder="••••••••" />
        </label>

        {error && <p className="admin-login__error">{error}</p>}

        <button type="submit" className="btn btn--gold btn--block" disabled={submitting}>
          {submitting ? 'Входим…' : 'Войти'}
        </button>
      </form>
    </div>
  );
}
