'use client';

import { useRef } from 'react';
import { T } from '@/context/AppProviders';

// Longer than the gap between the clicks of a double click.
const REPEAT_CLICK_MS = 400;

// Closing the dialog uncovers the page, so the second click of a double click
// would land on whatever lies under the pointer. Drop that one click.
function dropRepeatClick() {
  const drop = (e) => {
    e.stopPropagation();
    e.preventDefault();
  };
  const options = { capture: true, once: true };
  document.addEventListener('click', drop, options);
  setTimeout(() => document.removeEventListener('click', drop, options), REPEAT_CLICK_MS);
}

/**
 * A sign-out button that asks first. The native modal <dialog> brings the focus
 * trap and Esc; «Остаться» comes first in it, so it takes the initial focus.
 * `onConfirm` runs only from «Выйти», and only once, because that click closes
 * the dialog before anything else can land on it. `detail` is 0 for a keyboard
 * press, which no second click follows.
 */
export default function SignOutButton({ onConfirm, className, style, children }) {
  const dialogRef = useRef(null);

  function close(e) {
    if (e.detail > 0) dropRepeatClick();
    dialogRef.current?.close();
  }

  function confirm(e) {
    close(e);
    onConfirm();
  }

  return (
    <>
      <button type="button" className={className} style={style} onClick={() => dialogRef.current?.showModal()}>
        {children}
      </button>
      <dialog
        ref={dialogRef}
        className="signout-dialog"
        aria-labelledby="signout-dialog-title"
        onClick={(e) => {
          // The body fills the dialog, so only the backdrop targets it directly.
          if (e.target === dialogRef.current) close(e);
        }}
      >
        <div className="signout-dialog__body">
          <h2 id="signout-dialog-title" className="signout-dialog__title">
            <T ru="Выйти из аккаунта?" kz="Аккаунттан шығу керек пе?" en="Sign out?" />
          </h2>
          <p className="signout-dialog__text">
            <T
              ru="Вы уверены, что хотите выйти?"
              kz="Аккаунттан шығуға сенімдісіз бе?"
              en="Are you sure you want to sign out?"
            />
          </p>
          <button type="button" className="btn btn--gold" onClick={close}>
            <T ru="Остаться" kz="Қалу" en="Stay" />
          </button>
          <button type="button" className="btn signout-dialog__confirm" onClick={confirm}>
            <T ru="Выйти" kz="Шығу" en="Sign out" />
          </button>
        </div>
      </dialog>
    </>
  );
}
