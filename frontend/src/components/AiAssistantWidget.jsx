'use client';

import { useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import { T, useLang } from '@/context/AppProviders';
import { aiAssistantApi } from '@/lib/aiAssistantApi';
import { formatPrice } from '@/lib/format';

// AI event-planning assistant — Этап 1 "минимальный работающий прототип".
// Deliberately its own component/state, never importing useManagerChat or
// anything from FloatingManagerWidget.jsx — see backend/internal/
// aiassistant's own package doc on why these stay two separate features.
// Conversation history lives only in this component's state and is resent
// whole on every turn (no server-side thread to reopen, unlike Manager
// Chat's own start()/get()) — a page refresh starts a fresh conversation,
// a known stage-1 limitation.

const SUGGESTIONS = {
  ru: ['Нужен зал в Алматы на 120 гостей, бюджет 3 млн ₸', 'Подберите ресторан на день рождения'],
  kz: ['Алматыда 120 қонаққа арналған зал керек, бюджет 3 млн ₸', 'Туған күнге мейрамхана таңдап беріңізші'],
  en: ['I need a venue in Almaty for 120 guests, budget 3M KZT', 'Help me pick a restaurant for a birthday'],
};

export default function AiAssistantWidget() {
  const { lang } = useLang();
  const [isOpen, setIsOpen] = useState(false);
  const [messages, setMessages] = useState([]); // [{ role, content, listings? }]
  const [input, setInput] = useState('');
  const [sending, setSending] = useState(false);
  const [error, setError] = useState('');
  const [unavailable, setUnavailable] = useState(false);
  const threadRef = useRef(null);
  const panelRef = useRef(null);

  useEffect(() => {
    if (!isOpen) return;
    function onKeyDown(e) {
      if (e.key === 'Escape') setIsOpen(false);
    }
    document.addEventListener('keydown', onKeyDown);
    panelRef.current?.focus();
    return () => document.removeEventListener('keydown', onKeyDown);
  }, [isOpen]);

  useEffect(() => {
    if (!threadRef.current) return;
    threadRef.current.scrollTop = threadRef.current.scrollHeight;
  }, [messages, sending]);

  async function send(text) {
    const body = text.trim();
    if (!body || sending) return;
    setError('');
    const nextMessages = [...messages, { role: 'user', content: body }];
    setMessages(nextMessages);
    setInput('');
    setSending(true);
    try {
      const data = await aiAssistantApi.chat(
        nextMessages.map((m) => ({ role: m.role, content: m.content })),
        lang
      );
      setMessages((prev) => [...prev, { role: 'assistant', content: data.reply, listings: data.listings || [] }]);
    } catch (err) {
      if (err.unavailable) {
        setUnavailable(true);
      } else {
        setError(
          lang === 'kz'
            ? 'Хабарлама жіберілмеді. Қайта көріңіз.'
            : lang === 'en'
              ? "Couldn't send the message. Please try again."
              : 'Не удалось отправить сообщение. Попробуйте ещё раз.'
        );
      }
    } finally {
      setSending(false);
    }
  }

  function handleSubmit(e) {
    e.preventDefault();
    send(input);
  }

  return (
    <div className="ai-assistant-widget">
      {isOpen && (
        <div
          className="ai-assistant-widget__panel manager-widget__panel"
          role="dialog"
          aria-label={lang === 'kz' ? 'MEREYTOI ИИ-көмекшісі' : 'ИИ-помощник MEREYTOI'}
          ref={panelRef}
          tabIndex={-1}
        >
          <div className="manager-widget__panel-head">
            <span className="manager-widget__panel-title">
              <span className="manager-widget__panel-dot" aria-hidden="true"></span>
              <T ru="ИИ-помощник MEREYTOI" kz="MEREYTOI ИИ-көмекшісі" en="MEREYTOI AI assistant" />
            </span>
            <button
              type="button"
              className="manager-widget__panel-close"
              onClick={() => setIsOpen(false)}
              aria-label={lang === 'kz' ? 'Жабу' : 'Закрыть'}
            >
              ×
            </button>
          </div>

          <div className="manager-widget__body manager-widget__body--chat">
            {unavailable && (
              <p className="manager-chat-empty">
                <T
                  ru="ИИ-помощник временно недоступен. Напишите менеджеру — он поможет подобрать вариант."
                  kz="ИИ-көмекші уақытша қолжетімсіз. Менеджерге жазыңыз — ол көмектеседі."
                  en="The AI assistant is temporarily unavailable. Please message the manager instead."
                />
              </p>
            )}

            {!unavailable && (
              <div className="manager-chat-thread" ref={threadRef}>
                {messages.length === 0 && (
                  <p className="manager-chat-empty">
                    <T
                      ru="Опишите мероприятие — город, число гостей, бюджет — и я подберу подходящие варианты."
                      kz="Іс-шараны сипаттаңыз — қала, қонақ саны, бюджет — мен қолайлы нұсқаларды таңдап беремін."
                      en="Describe your event — city, guest count, budget — and I'll find matching options."
                    />
                  </p>
                )}
                {messages.map((m, i) => (
                  <div key={i} className={`manager-chat-msg manager-chat-msg--${m.role === 'user' ? 'out' : 'in'}`}>
                    <p className="manager-chat-msg__text">{m.content}</p>
                    {m.listings && m.listings.length > 0 && (
                      <div className="ai-assistant-listings">
                        {m.listings.map((l) => (
                          <div className="ai-assistant-listing" key={l.id}>
                            <div className="ai-assistant-listing__name">{l.name}</div>
                            <div className="ai-assistant-listing__meta">
                              {l.city && <span>{l.city}</span>}
                              {l.capacity_known ? (
                                <span>{lang === 'kz' ? `${l.capacity} қонаққа дейін` : `до ${l.capacity} гостей`}</span>
                              ) : (
                                <span className="ai-assistant-listing__note">
                                  <T ru="вместимость уточняется" kz="сыйымдылығы нақтыланады" en="capacity to confirm" />
                                </span>
                              )}
                              {l.price_known ? (
                                <span>
                                  {formatPrice(l.price_from)}
                                  {l.price_unit === 'per_guest' ? (lang === 'kz' ? '/адам' : '/чел.') : ''}
                                </span>
                              ) : (
                                <span className="ai-assistant-listing__note">
                                  <T ru="цена уточняется" kz="бағасы нақтыланады" en="price to confirm" />
                                </span>
                              )}
                            </div>
                            <Link href={l.url} className="ai-assistant-listing__link" onClick={() => setIsOpen(false)}>
                              <T ru="Открыть →" kz="Ашу →" en="Open →" />
                            </Link>
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                ))}
                {sending && <p className="manager-chat-empty">…</p>}
              </div>
            )}

            {!unavailable && messages.length === 0 && (
              <div className="manager-chat-chips">
                {SUGGESTIONS[lang === 'kz' || lang === 'en' ? lang : 'ru'].map((text) => (
                  <button type="button" key={text} className="manager-chat-chip" onClick={() => send(text)}>
                    {text}
                  </button>
                ))}
              </div>
            )}

            {error && <p className="admin-login__error">{error}</p>}

            {!unavailable && (
              <form className="manager-chat-composer" onSubmit={handleSubmit}>
                <textarea
                  rows={1}
                  maxLength={1000}
                  value={input}
                  onChange={(e) => setInput(e.target.value)}
                  placeholder={
                    lang === 'kz' ? 'Мысалы: Алматыда 100 қонаққа зал...' : lang === 'en' ? 'e.g. A venue in Almaty for 100 guests...' : 'Например: зал в Алматы на 100 гостей...'
                  }
                  onKeyDown={(e) => {
                    if (e.key === 'Enter' && !e.shiftKey) {
                      e.preventDefault();
                      send(input);
                    }
                  }}
                />
                <button type="submit" className="btn btn--gold" disabled={sending || !input.trim()}>
                  →
                </button>
              </form>
            )}
          </div>
        </div>
      )}

      {!isOpen && (
        <div className="ai-assistant-widget__launcher">
          <button
            type="button"
            className="ai-assistant-widget__avatar-btn"
            onClick={() => setIsOpen(true)}
            aria-label={lang === 'kz' ? 'ИИ-көмекшіні ашу' : 'Открыть ИИ-помощника'}
            aria-haspopup="dialog"
            aria-expanded={isOpen}
          >
            ✨
          </button>
        </div>
      )}
    </div>
  );
}
