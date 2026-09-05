'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { T, useLang, useManagerChat } from '@/context/AppProviders';
import { useAuth } from '@/context/AuthContext';
import { createBooking } from '@/lib/bookingApi';
import { managerChatApi } from '@/lib/managerChatApi';
import { formatPrice } from '@/lib/format';
import { formatEventDate, timeAgo } from '@/lib/eventHelpers';
import { AGENCY_WHATSAPP_DIGITS } from '@/lib/agencyContact';

const GREETING_KEY = 'mereytoi_manager_greeting_shown';
const AUTO_DELAY = 800;
const MESSAGE_MAX = 1000;
// Real two-way chat only exists for logged-in customers (see
// backend/internal/models/manager_chat.go's own doc comment on why) —
// comfortably slower than the ~3s event-discussion poll, this is a
// lead-in/support chat, not a live team discussion.
const CHAT_POLL_MS = 5000;

const SUGGESTION_CHIPS = [
  { ru: 'Подобрать услуги', kz: 'Қызметтерді таңдау', text: { ru: 'Помогите подобрать услуги для нашего мероприятия', kz: 'Іс-шарамызға қызметтерді таңдауға көмектесіңіз' } },
  { ru: 'Рассчитать стоимость', kz: 'Құнын есептеу', text: { ru: 'Подскажите, пожалуйста, примерную стоимость', kz: 'Болжамды құнын айтып жіберіңізші' } },
  { ru: 'Свободна ли дата?', kz: 'Күн бос па?', text: { ru: 'Подскажите, свободна ли нужная нам дата?', kz: 'Бізге керек күн бос па, айтып жіберіңізші?' } },
  { ru: 'Вопрос по услуге', kz: 'Қызмет туралы сұрақ', text: { ru: 'У меня вопрос по услуге', kz: 'Қызмет бойынша сұрағым бар' } },
];

function pushDataLayer(event) {
  if (typeof window === 'undefined') return;
  window.dataLayer = window.dataLayer || [];
  window.dataLayer.push({ event });
}

export default function FloatingManagerWidget() {
  const pathname = usePathname();
  const { lang } = useLang();
  const { isAuthenticated } = useAuth();
  const { isOpen, chatContext, openChat, closeChat } = useManagerChat();

  const [view, setView] = useState('menu'); // 'menu' | 'message' | 'callback' | 'success' | 'chat'
  const [name, setName] = useState('');
  const [phone, setPhone] = useState('');
  const [message, setMessage] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');

  // ---- Real chat state (authenticated only) ----
  const [conversation, setConversation] = useState(null);
  const [chatMessages, setChatMessages] = useState(null);
  const [chatText, setChatText] = useState('');
  const [chatLoading, setChatLoading] = useState(false);
  const [chatSending, setChatSending] = useState(false);
  const [chatError, setChatError] = useState('');
  const chatInputRef = useRef(null);

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
    closeChat();
    setView('menu');
    setError('');
    pushDataLayer('manager_widget_close');
  }, [closeChat]);

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
  // via the ref so it still respects /admin if the timer lands there. Same
  // full panel on every viewport — mobile gets a more compact layout via
  // CSS, not a separate lower-visibility teaser bubble.
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
      setView('menu');
      openChat(null);
      pushDataLayer('manager_widget_open');
    }, AUTO_DELAY);

    return () => clearTimeout(timer);
    // openChat is a stable useCallback from context (see AppProviders.jsx),
    // so listing it here doesn't change this effect's actual behavior —
    // it still only ever runs once per page load, since nothing else in
    // this dependency list changes after mount either.
  }, [openChat]);

  useEffect(() => {
    if (!isOpen) return;
    function onKeyDown(e) {
      if (e.key === 'Escape') closePanel();
    }
    document.addEventListener('keydown', onKeyDown);
    return () => document.removeEventListener('keydown', onKeyDown);
  }, [isOpen, closePanel]);

  useEffect(() => {
    if (!isOpen) return;
    // The callback form's phone input focuses itself (autoFocus, only ever
    // reached by a real tap on "Позвоните мне") — moving focus to the panel
    // here too would immediately steal it back. The chat view focuses its
    // own composer in a separate effect below (brief section 20).
    if (view === 'callback' || view === 'chat') return;
    panelRef.current?.focus();
  }, [isOpen, view]);

  // Restore focus to the avatar button once it has actually remounted after
  // a close — doing this inside closePanel() itself was too early: the
  // button doesn't exist in the DOM until React re-renders past isOpen=false.
  useEffect(() => {
    if (wasOpenRef.current && !isOpen) avatarBtnRef.current?.focus();
    wasOpenRef.current = isOpen;
  }, [isOpen]);

  // A context-carrying openChat() (from a service page's "Спросить
  // менеджера" or a shortlist's "Спросить MEREYTOI") means: skip the
  // greeting menu entirely and go straight to chat — the whole point of
  // section 17/20 is that the visitor never has to explain what page
  // they're on. Only for authenticated users; a guest gets the context
  // folded into the old lead-capture message instead (see handleSubmitMessage).
  useEffect(() => {
    if (isOpen && chatContext && isAuthenticated) {
      setView('chat');
    }
  }, [isOpen, chatContext, isAuthenticated]);

  // Loads (or starts) the conversation for the current context whenever the
  // chat view is actually shown — safe to call repeatedly with the same
  // context (backend reuses the one open conversation, brief section 17/21).
  useEffect(() => {
    if (!isOpen || view !== 'chat' || !isAuthenticated) return;
    let cancelled = false;
    setChatLoading(true);
    setChatError('');
    // Clears any previous context's thread immediately — a "Спросить
    // менеджера" click on a *different* service while the widget is
    // already open in chat view must not flash the old service's messages
    // while the new context's conversation loads.
    setConversation(null);
    setChatMessages(null);
    managerChatApi
      .start('', { eventId: chatContext?.eventId, listingId: chatContext?.listingId })
      .then((data) => {
        if (cancelled) return;
        setConversation(data.conversation);
        setChatMessages(data.messages || []);
      })
      .catch(() => {
        // A genuine network/auth failure (an empty-message "peek" itself
        // never errors — see the backend's own doc comment on Start) —
        // just fall back to the empty/chips state rather than blocking
        // the panel on an error the user can't do anything about yet.
        if (!cancelled) setChatMessages([]);
      })
      .finally(() => {
        if (!cancelled) setChatLoading(false);
      });
    return () => { cancelled = true; };
    // Keyed on the two ids that actually matter (not the whole chatContext
    // object, which is a fresh reference from the caller on every
    // openChat() call) so this doesn't refire on every parent re-render.
  }, [isOpen, view, isAuthenticated, chatContext?.eventId, chatContext?.listingId]);

  // Poll for the manager's replies while the chat is actually open — same
  // pattern as CommentThread's discussion poll, just a slower cadence
  // (this isn't a live team discussion, brief section 9's spirit applies
  // here too even though it wasn't spelled out for this feature).
  useEffect(() => {
    if (!isOpen || view !== 'chat' || !conversation?.id) return;
    let cancelled = false;
    const id = setInterval(() => {
      if (document.hidden) return;
      managerChatApi
        .get(conversation.id)
        .then((data) => {
          if (!cancelled) setChatMessages(data.messages || []);
        })
        .catch(() => {});
    }, CHAT_POLL_MS);
    return () => { cancelled = true; clearInterval(id); };
  }, [isOpen, view, conversation?.id]);

  useEffect(() => {
    if (isOpen && view === 'chat' && !chatLoading) {
      chatInputRef.current?.focus();
    }
  }, [isOpen, view, chatLoading]);

  if (pathname.startsWith('/admin')) return null;

  function openPanel(nextView) {
    clearAutoCloseTimer();
    setError('');
    setView(nextView);
    openChat(null);
    pushDataLayer('manager_widget_open');
  }

  function openChatView() {
    clearAutoCloseTimer();
    setChatError('');
    setView('chat');
    openChat(null);
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
      // A guest has no persistent chat identity (see managerChatApi's own
      // doc comment) — the service/event context is folded into the
      // message text instead, so the manager still gets it either way
      // (brief section 17's spirit, just via the pre-existing lead form
      // rather than a live thread).
      const contextLine = chatContext?.listingName
        ? `Услуга: ${chatContext.listingName}${chatContext.listingPrice ? ` (${formatPrice(chatContext.listingPrice)})` : ''}. `
        : '';
      await createBooking({
        name: name.trim(),
        phone: phone.trim(),
        message: `[Виджет менеджера · сообщение] ${contextLine}${message.trim()}`,
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

  async function sendChat(body) {
    const text = body.trim();
    if (!text || chatSending) return;
    setChatSending(true);
    setChatError('');
    setChatText('');
    try {
      let data;
      if (conversation?.id) {
        data = await managerChatApi.addMessage(conversation.id, text);
      } else {
        data = await managerChatApi.start(text, { eventId: chatContext?.eventId, listingId: chatContext?.listingId });
      }
      setConversation(data.conversation);
      setChatMessages(data.messages || []);
      pushDataLayer('manager_chat_message_sent');
    } catch (err) {
      setChatText(text);
      setChatError(err.message || (lang === 'kz' ? 'Хабарлама жіберілмеді' : 'Не удалось отправить сообщение'));
    } finally {
      setChatSending(false);
    }
  }

  function handleChatSubmit(e) {
    e.preventDefault();
    sendChat(chatText);
  }

  function handleChipClick(chip) {
    // Populate + focus, never auto-send — the user can see and edit exactly
    // what's about to go to the manager before it does (brief section 18).
    setChatText(chip.text[lang] || chip.text.ru);
    chatInputRef.current?.focus();
  }

  const whatsappHref = `https://wa.me/${AGENCY_WHATSAPP_DIGITS}?text=${encodeURIComponent(
    lang === 'kz' ? 'Сәлеметсіз бе! MEREYTOI қызметтері туралы білгім келеді.' : 'Здравствуйте! Хочу узнать подробнее об услугах MEREYTOI.'
  )}`;

  // The conversation's own nested event/listing (once it exists
  // server-side) is the authoritative source — but before the visitor has
  // typed a first message there may be no conversation yet at all, and the
  // context block still has to show immediately (brief section 17's whole
  // point). The calling page already has this data loaded (a service
  // detail page knows its own name/price; an event workspace page already
  // has the event object) and passes it straight into openChat(), so that's
  // the fallback while nothing has round-tripped to the backend yet.
  const ctxEvent = conversation?.event || (chatContext?.eventTitle ? {
    title: chatContext.eventTitle,
    event_date: chatContext.eventDate,
    city: chatContext.eventCity,
    guests: chatContext.eventGuests,
    budget_total: chatContext.eventBudget,
  } : null);
  const ctxListing = conversation?.listing || (chatContext?.listingName ? {
    id: chatContext.listingId,
    name_ru: chatContext.listingName,
    name_kz: chatContext.listingName,
    price: chatContext.listingPrice,
  } : null);

  return (
    <div className="manager-widget">
      {isOpen && (
        <div className="manager-widget__panel" role="dialog" aria-label={lang === 'kz' ? 'MEREYTOI менеджері' : 'Менеджер MEREYTOI'} ref={panelRef} tabIndex={-1}>
          <div className="manager-widget__panel-head">
            <span className="manager-widget__panel-title">
              <span className="manager-widget__panel-dot" aria-hidden="true"></span>
              <T ru="Менеджер MEREYTOI" kz="MEREYTOI менеджері" />
            </span>
            <button type="button" className="manager-widget__panel-close" onClick={closePanel} aria-label={lang === 'kz' ? 'Жабу' : 'Закрыть'}>
              ×
            </button>
          </div>

          {view === 'menu' && (
            <div className="manager-widget__body">
              <p className="manager-widget__greeting-title">
                <T ru="Здравствуйте! 👋" kz="Сәлеметсіз бе! 👋" />
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
                    if (isAuthenticated) openChatView();
                    else {
                      setView('message');
                      setError('');
                    }
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

          {view === 'chat' && (
            <div className="manager-widget__body manager-widget__body--chat">
              <button
                type="button"
                className="manager-widget__back"
                onClick={() => {
                  setView('menu');
                  setChatError('');
                }}
              >
                ← <T ru="Назад" kz="Артқа" />
              </button>

              {/* Event metadata (brief section 19) — shown once as context,
                  never repeated per message. */}
              {ctxEvent && (
                <div className="manager-chat-ctx manager-chat-ctx--event">
                  <div className="manager-chat-ctx__title">{ctxEvent.title}</div>
                  <div className="manager-chat-ctx__meta">
                    {formatEventDate(ctxEvent.event_date, lang) && <span>{formatEventDate(ctxEvent.event_date, lang)}</span>}
                    {ctxEvent.city && <span>{ctxEvent.city}</span>}
                    {ctxEvent.guests > 0 && <span>{ctxEvent.guests} {lang === 'kz' ? 'қонақ' : 'гостей'}</span>}
                  </div>
                  {ctxEvent.budget_total > 0 && (
                    <div className="manager-chat-ctx__budget">
                      <T ru="Бюджет" kz="Бюджет" />: {formatPrice(ctxEvent.budget_total)}
                    </div>
                  )}
                </div>
              )}

              {/* Service context (brief section 17) — compact, above the
                  first message/composer, with a deep link back to it
                  (section 22 — always safe, /services/:id is public). */}
              {ctxListing && (
                <div className="manager-chat-ctx manager-chat-ctx--service">
                  <div className="manager-chat-ctx__label"><T ru="Вопрос по услуге" kz="Қызмет туралы сұрақ" en="Question about a service" /></div>
                  <div className="manager-chat-ctx__title">{lang === 'kz' ? ctxListing.name_kz : ctxListing.name_ru}</div>
                  {ctxListing.price > 0 && <div className="manager-chat-ctx__price">{formatPrice(ctxListing.price)}</div>}
                  <Link href={`/services/${ctxListing.id}`} className="manager-chat-ctx__link" onClick={closePanel}>
                    <T ru="Открыть услугу →" kz="Қызметті ашу →" en="Open service →" />
                  </Link>
                </div>
              )}

              <div className="manager-chat-thread">
                {chatLoading && <div className="ws-skeleton" style={{ height: 50 }} />}
                {!chatLoading && chatMessages?.length === 0 && (
                  <p className="manager-chat-empty">
                    <T ru="Задайте вопрос — менеджер ответит в ближайшее время." kz="Сұрағыңызды қойыңыз — менеджер жақын арада жауап береді." />
                  </p>
                )}
                {!chatLoading && chatMessages?.map((m) => (
                  <div className={`manager-chat-msg manager-chat-msg--${m.sender_type === 'user' ? 'out' : 'in'}`} key={m.id}>
                    <p className="manager-chat-msg__text">{m.body}</p>
                    <span className="manager-chat-msg__time">{timeAgo(m.created_at, lang)}</span>
                  </div>
                ))}
              </div>

              {!chatLoading && (!chatMessages || chatMessages.length === 0) && (
                <div className="manager-chat-chips">
                  {SUGGESTION_CHIPS.map((chip) => (
                    <button type="button" key={chip.ru} className="manager-chat-chip" onClick={() => handleChipClick(chip)}>
                      {lang === 'kz' ? chip.kz : chip.ru}
                    </button>
                  ))}
                </div>
              )}

              {chatError && <p className="admin-login__error">{chatError}</p>}

              <form className="manager-chat-composer" onSubmit={handleChatSubmit}>
                <textarea
                  ref={chatInputRef}
                  rows={1}
                  maxLength={MESSAGE_MAX}
                  value={chatText}
                  onChange={(e) => setChatText(e.target.value)}
                  placeholder={lang === 'kz' ? 'Хабарлама жазу...' : 'Написать сообщение...'}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); sendChat(chatText); }
                  }}
                />
                <button type="submit" className="btn btn--gold" disabled={chatSending || !chatText.trim()}>→</button>
              </form>
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
              {chatContext?.listingName && (
                <div className="manager-chat-ctx manager-chat-ctx--service">
                  <div className="manager-chat-ctx__label"><T ru="Вопрос по услуге" kz="Қызмет туралы сұрақ" /></div>
                  <div className="manager-chat-ctx__title">{chatContext.listingName}</div>
                  {chatContext.listingPrice > 0 && <div className="manager-chat-ctx__price">{formatPrice(chatContext.listingPrice)}</div>}
                </div>
              )}
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

      {!isOpen && (
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
