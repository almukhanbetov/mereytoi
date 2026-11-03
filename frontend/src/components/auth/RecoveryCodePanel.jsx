'use client';

import { useState } from 'react';
import { T } from '@/context/AppProviders';

/** Shows a freshly issued one-time backup code — after registration, after
 * recovering the password with the previous code, or after replacing it in
 * the profile. The code lives only in this component's props: it is never
 * written to localStorage or anywhere else, and this is the only time it is
 * shown. `onDone` becomes available once the person confirms they saved it. */
export default function RecoveryCodePanel({ code, onDone, doneLabel }) {
  const [saved, setSaved] = useState(false);
  const [copied, setCopied] = useState(false);

  async function handleCopy() {
    try {
      await navigator.clipboard.writeText(code);
      setCopied(true);
    } catch {
      setCopied(false);
    }
  }

  return (
    <div className="recovery-code">
      <p className="recovery-code__title">
        <T ru="Ваш резервный код" kz="Сіздің резервтік кодыңыз" en="Your backup code" />
      </p>
      <code className="recovery-code__value" data-testid="recovery-code">{code}</code>
      <button type="button" className="btn btn--outline btn--block" onClick={handleCopy}>
        {copied
          ? <T ru="Скопировано" kz="Көшірілді" en="Copied" />
          : <T ru="Скопировать код" kz="Кодты көшіру" en="Copy code" />}
      </button>
      <p className="recovery-code__warning">
        <T
          ru="Сохраните код в надёжном месте. Он понадобится для восстановления пароля. Код показывается только сейчас — посмотреть его позже нельзя."
          kz="Кодты сенімді жерде сақтаңыз. Ол құпиясөзді қалпына келтіру үшін қажет болады. Код тек қазір көрсетіледі — кейін оны көру мүмкін емес."
          en="Keep this code somewhere safe. You will need it to recover your password. It is shown only now — you can't view it again later."
        />
      </p>
      <label className="recovery-code__confirm">
        <input type="checkbox" checked={saved} onChange={(e) => setSaved(e.target.checked)} />
        <span><T ru="Я сохранил код" kz="Мен кодты сақтадым" en="I have saved the code" /></span>
      </label>
      <button type="button" className="btn btn--gold btn--block" disabled={!saved} onClick={onDone}>
        {doneLabel || <T ru="Готово" kz="Дайын" en="Done" />}
      </button>
    </div>
  );
}
