'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { usePathname } from 'next/navigation';
import { T, useLang } from '@/context/AppProviders';
import { createBooking } from '@/lib/bookingApi';
import { AGENCY_WHATSAPP_DIGITS } from '@/lib/agencyContact';

const GREETING_KEY = 'mereytoi_manager_greeting_shown';
const AUTO_DELAY = 3000;
const MESSAGE_MAX = 1000;
const MOBILE_BREAKPOINT = 480;

function pushDataLayer(event) {
  if (typeof window === 'undefined') return;
  window.dataLayer = window.dataLayer || [];
  window.dataLayer.push({ event });
}

export default function FloatingManagerWidget() {
  const pathname = usePathname();
  const { lang } = useLang();

  const [isOpen, setIsOpen] = useState(false);
  const [view, setView] = useState('menu'); // 'menu' | 'message' | 'callback' | 'success'
  const [teaserVisible, setTeaserVisible] = useState(false);
  const [name, setName] = useState('');
  const [phone, setPhone] = useState('');
  const [message, setMessage] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');

  const panelRef = useRef(null);
  const avatarBtnRef = useRef(null);
  const pathnameRef = useRef(pathname);
  const autoCloseTimerRef = useRef(null);
  const wasOpenRef = useRef(false);

  function clearAutoCloseTimer() {
    if (autoCloseTimerRef.current) {
      clearTimeout(autoCloseTimerRef.current);
      autoCloseTimerRef.current = null;
    }
  }

  // Stable identity (only refs/setters/module-level fns inside) so it can sit
  // in the Escape-key effect's deps without retriggering that effect on
  // every render.
  const closePanel = useCallback(() => {
    // The panel has no exit animation — it unmounts the instant isOpen
    // flips false — so resetting view/error here is invisible to the user.
    if (autoCloseTimerRef.current) {
      clearTimeout(autoCloseTimerRef.current);
      autoCloseTimerRef.current = null;
    }
    setIsOpen(false);
    setView('menu');
    setError('');
    pushDataLayer('manager_widget_close');
  }, []);

  // Auto-collapses the success screen after a few seconds — cancelled by any
  // manual close/reopen in the meantime so it can never stomp a session the
  // user has already moved on from.
  function scheduleAutoClose() {
    clearAutoCloseTimer();
    autoCloseTimerRef.current = setTimeout(() => {
      autoCloseTimerRef.current = null;
      closePanel();
    }, 4000);
  }

  useEffect(() => {
    pathnameRef.current = pathname;
  }, [pathname]);

  // Delayed greeting, once per browser session — fires exactly once on the
  // page the visitor first landed on (deps: [] so client-side navigation
  // never restarts or repeats it); the pathname is re-checked at fire time
  // via the ref so it still respects /admin if the timer lands there.
  useEffect(() => {
    if (typeof window === 'undefined') return;
    let alreadyShown = null;
    try {
      alreadyShown = window.sessionStorage.getItem(GREETING_KEY);
    } catch {
      /* sessionStorage unavailable (private mode etc.) — skip auto-greeting */
      return;
    }
    if (alreadyShown) return;

    const timer = setTimeout(() => {
      try {
        window.sessionStorage.setItem(GREETING_KEY, '1');
      } catch {
        /* ignore */
      }
      if (pathnameRef.current.startsWith('/admin')) return;
      if (window.innerWidth <= MOBILE_BREAKPOINT) {
        setTeaserVisible(true);
      } else {
        setView('menu');
        setIsOpen(true);
        pushDataLayer('manager_widget_open');
      }
    }, AUTO_DELAY);

    return () => clearTimeout(timer);
  }, []);

  useEffect(() => {
    if (!isOpen) return;
    function onKeyDown(e) {
      if (e.key === 'Escape') closePanel();
    }
    document.addEventListener('keydown', onKeyDown);
    return () => document.removeEventListener('keydown', onKeyDown);
  }, [isOpen, closePanel]);

  useEffect(() => {
    if (isOpen) panelRef.current?.focus();
  }, [isOpen, view]);

  // Restore focus to the avatar button once it has actually remounted after
  // a close — doing this inside closePanel() itself was too early: the
  // button doesn't exist in the DOM until React re-renders past isOpen=false.
  useEffect(() => {
    if (wasOpenRef.current && !isOpen) avatarBtnRef.current?.focus();
    wasOpenRef.current = isOpen;
  }, [isOpen]);

  if (pathname.startsWith('/admin')) return null;

  function openPanel(nextView) {
    clearAutoCloseTimer();
    setTeaserVisible(false);
    setError('');
    setView(nextView);
    setIsOpen(true);
    pushDataLayer('manager_widget_open');
  }

  async function handleSubmitMessage(e) {
    e.preventDefault();
    if (!name.trim() || !phone.trim() || !message.trim()) {
      setError(lang === 'kz' ? 'Атыңызды, телефоныңызды және хабарламаны толтырыңыз' : 'Заполните имя, телефон и сообщение');
      return;
    }
    setError('');
    setSubmitting(true);
    try {
      await createBooking({
        name: name.trim(),
        phone: phone.trim(),
        message: `[Виджет менеджера · сообщение] ${message.trim()}`,
        items: [],
      });
      pushDataLayer('manager_message_submit');
      setMessage('');
      setView('success');
      scheduleAutoClose();
    } catch {
      setError(lang === 'kz' ? 'Өтінімді жіберу сәтсіз аяқталды. Қайта көріңіз.' : 'Не удалось отправить заявку. Попробуйте ещё раз.');
    } finally {
      setSubmitting(false);
    }
  }

  async function handleSubmitCallback(e) {
    e.preventDefault();
    if (!phone.trim()) {
      setError(lang === 'kz' ? 'Телефон нөмірін енгізіңіз' : 'Введите номер телефона');
      return;
    }
    setError('');
    setSubmitting(true);
    try {
      await createBooking({
        name: name.trim() || (lang === 'kz' ? 'Қоңырау шалу' : 'Обратный звонок'),
        phone: phone.trim(),
        message: '[Виджет менеджера · обратный звонок]',
        items: [],
      });
      pushDataLayer('manager_callback_submit');
      setView('success');
      scheduleAutoClose();
    } catch {
      setError(lang === 'kz' ? 'Өтінімді жіберу сәтсіз аяқталды. Қайта көріңіз.' : 'Не удалось отправить заявку. Попробуйте ещё раз.');
    } finally {
      setSubmitting(false);
    }
  }

  const whatsappHref = `https://wa.me/${AGENCY_WHATSAPP_DIGITS}?text=${encodeURIComponent(
    lang === 'kz' ? 'Сәлеметсіз бе! MEREYTOI қызметтері туралы білгім келеді.' : 'Здравствуйте! Хочу узнать подробнее об услугах MEREYTOI.'
  )}`;

  return (
    <div className="manager-widget">
      {teaserVisible && !isOpen && (
        <div
          className="manager-widget__teaser"
          role="button"
          tabIndex={0}
          onClick={() => openPanel('menu')}
          onKeyDown={(e) => {
            if (e.key === 'Enter' || e.key === ' ') {
              e.preventDefault();
              openPanel('menu');
            }
          }}
          aria-label={lang === 'kz' ? 'Менеджермен чатты ашу' : 'Открыть чат с менеджером'}
        >
          <button
            type="button"
            className="manager-widget__teaser-close"
            onClick={(e) => {
              e.stopPropagation();
              setTeaserVisible(false);
            }}
            aria-label={lang === 'kz' ? 'Жабу' : 'Закрыть'}
          >
            ×
          </button>
          <T ru="Здравствуйте! Поможем с тоем 🎉" kz="Сәлеметсіз бе! Тойға көмектесеміз 🎉" />
        </div>
      )}

      {isOpen && (
        <div className="manager-widget__panel" role="dialog" aria-label={lang === 'kz' ? 'MEREYTOI менеджері' : 'Менеджер MEREYTOI'} ref={panelRef} tabIndex={-1}>
          <div className="manager-widget__panel-head">
            <span className="manager-widget__panel-title">
              <T ru="Менеджер MEREYTOI" kz="MEREYTOI менеджері" />
            </span>
            <button type="button" className="manager-widget__panel-close" onClick={closePanel} aria-label={lang === 'kz' ? 'Жабу' : 'Закрыть'}>
              ×
            </button>
          </div>

          {view === 'menu' && (
            <div className="manager-widget__body">
              <p className="manager-widget__greeting-title">
                <T ru="Здравствуйте!" kz="Сәлеметсіз бе!" />
              </p>
              <p className="manager-widget__greeting-text">
                <T ru="Планируете той?" kz="Той жоспарлап жатырсыз ба?" />
                <br />
                <T ru="Поможем подобрать услуги и рассчитать стоимость." kz="Қызметтерді таңдап, құнын есептеуге көмектесеміз." />
              </p>
              <div className="manager-widget__actions">
                <button
                  type="button"
                  className="btn btn--gold btn--block"
                  onClick={() => {
                    setView('message');
                    setError('');
                  }}
                >
                  <T ru="Написать" kz="Жазу" />
                </button>
                <button
                  type="button"
                  className="btn btn--outline btn--block"
                  onClick={() => {
                    setView('callback');
                    setError('');
                  }}
                >
                  <T ru="Позвоните мне" kz="Маған қоңырау шалыңыз" />
                </button>
              </div>
              <a className="manager-widget__whatsapp-link" href={whatsappHref} target="_blank" rel="noopener noreferrer" onClick={() => pushDataLayer('manager_whatsapp_click')}>
                <T ru="Написать в WhatsApp" kz="WhatsApp-қа жазу" /> →
              </a>
            </div>
          )}

          {view === 'message' && (
            <form className="manager-widget__body" onSubmit={handleSubmitMessage}>
              <button
                type="button"
                className="manager-widget__back"
                onClick={() => {
                  setView('menu');
                  setError('');
                }}
              >
                ← <T ru="Назад" kz="Артқа" />
              </button>
              <label className="manager-widget__field">
                <span>
                  <T ru="Ваше имя" kz="Атыңыз" />
                </span>
                <input type="text" value={name} onChange={(e) => setName(e.target.value)} required maxLength={150} placeholder={lang === 'kz' ? 'Атыңыз' : 'Ваше имя'} />
              </label>
              <label className="manager-widget__field">
                <span>
                  <T ru="Телефон" kz="Телефон" />
                </span>
                <input type="tel" value={phone} onChange={(e) => setPhone(e.target.value)} required maxLength={30} placeholder="+7 700 000 00 00" />
              </label>
              <label className="manager-widget__field">
                <span>
                  <T ru="Ваше сообщение" kz="Хабарламаңыз" />
                </span>
                <textarea rows={3} value={message} onChange={(e) => setMessage(e.target.value)} required maxLength={MESSAGE_MAX} placeholder={lang === 'kz' ? 'Хабарламаңыз' : 'Ваше сообщение'} />
              </label>
              {error && <p className="admin-login__error">{error}</p>}
              <button type="submit" className="btn btn--gold btn--block" disabled={submitting}>
                {submitting ? <T ru="Отправляем…" kz="Жіберілуде…" /> : <T ru="Отправить" kz="Жіберу" />}
              </button>
            </form>
          )}

          {view === 'callback' && (
            <form className="manager-widget__body" onSubmit={handleSubmitCallback}>
              <button
                type="button"
                className="manager-widget__back"
                onClick={() => {
                  setView('menu');
                  setError('');
                }}
              >
                ← <T ru="Назад" kz="Артқа" />
              </button>
              <p className="manager-widget__greeting-text">
                <T ru="Оставьте номер телефона, и наш менеджер свяжется с вами." kz="Телефон нөміріңізді қалдырыңыз, менеджеріміз сізбен байланысады." />
              </p>
              <label className="manager-widget__field">
                <span>
                  <T ru="Телефон" kz="Телефон" />
                </span>
                <input type="tel" value={phone} onChange={(e) => setPhone(e.target.value)} required maxLength={30} placeholder="+7 700 000 00 00" autoFocus />
              </label>
              {error && <p className="admin-login__error">{error}</p>}
              <button type="submit" className="btn btn--gold btn--block" disabled={submitting}>
                {submitting ? <T ru="Отправляем…" kz="Жіберілуде…" /> : <T ru="Заказать звонок" kz="Қоңырау шалуды тапсырыс беру" />}
              </button>
            </form>
          )}

          {view === 'success' && (
            <div className="manager-widget__body manager-widget__success">
              <p className="manager-widget__success-title">
                <T ru="Спасибо!" kz="Рахмет!" />
              </p>
              <p className="manager-widget__greeting-text">
                <T ru="Мы свяжемся с вами в ближайшее время." kz="Жақын арада сізбен байланысамыз." />
              </p>
            </div>
          )}
        </div>
      )}

      {!isOpen && !teaserVisible && (
        <div className="manager-widget__launcher">
          <button type="button" className="manager-widget__phone-btn" onClick={() => openPanel('callback')} aria-label={lang === 'kz' ? 'Қоңырау шалуды тапсырыс беру' : 'Заказать обратный звонок'}>
            ☎
          </button>
          <button
            type="button"
            className="manager-widget__avatar-btn"
            ref={avatarBtnRef}
            onClick={() => openPanel('menu')}
            aria-label={lang === 'kz' ? 'Менеджермен чатты ашу' : 'Открыть чат с менеджером'}
            aria-haspopup="dialog"
            aria-expanded={isOpen}
          >
            <span className="manager-widget__avatar-mark">M</span>
            <span className="manager-widget__online-dot" aria-hidden="true"></span>
          </button>
        </div>
      )}
    </div>
  );
}
