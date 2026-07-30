'use client';

import { useState } from 'react';

export default function PasswordInput({ value, onChange, ...rest }) {
  const [visible, setVisible] = useState(false);

  return (
    <div className="password-input">
      <input type={visible ? 'text' : 'password'} value={value} onChange={onChange} {...rest} />
      <button
        type="button"
        className="password-input__toggle"
        onClick={() => setVisible((v) => !v)}
        aria-label={visible ? 'Скрыть пароль' : 'Показать пароль'}
        tabIndex={-1}
      >
        {visible ? '🙈' : '👁️'}
      </button>
    </div>
  );
}
