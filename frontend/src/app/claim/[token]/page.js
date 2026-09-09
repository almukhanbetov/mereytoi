'use client';

import { use, useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { T } from '@/context/AppProviders';
import { useAuth } from '@/context/AuthContext';

/** The one bridge a brand-new "pending" account (see backend/internal/
 * handlers/onboarding.go) has into an actual session — reached either by
 * the in-page "Открыть мой той" button (BookingWorkspaceCTA.jsx, right
 * after a booking) or, once external delivery exists, by a link opened in
 * a completely fresh browser with no prior state at all — this page never
 * assumes anything beyond the token in its own URL. */
export default function ClaimPage({ params }) {
  const { token } = use(params);
  const router = useRouter();
  const { claim } = useAuth();
  const [state, setState] = useState({ status: 'loading' });
  const calledRef = useRef(false);

  useEffect(() => {
    // Claiming is a one-shot, single-use action server-side (brief section
    // 3/8) — a dev-mode double-effect-invoke must not turn into two real
    // requests, or the second would always see "already used".
    if (calledRef.current) return;
    calledRef.current = true;

    claim(token)
      .then(({ eventId }) => {
        setState({ status: 'success', eventId });
      })
      .catch((err) => {
        const message = err.message || '';
        if (message.includes('already used')) setState({ status: 'used' });
        else if (message.includes('expired')) setState({ status: 'expired' });
        else setState({ status: 'invalid' });
      });
    // `claim` is a stable useCallback from AuthContext — listing it here
    // doesn't change this effect's actual behavior (the calledRef guard
    // above is what actually prevents a second real request either way).
  }, [token, claim]);

  useEffect(() => {
    if (state.status === 'success' && state.eventId) {
      // ?welcome=1 — a one-time hint for EventWorkspaceShell.jsx to show
      // the first-login welcome modal; it's the shell's own localStorage
      // flag (per event, mirroring FloatingManagerWidget's existing
      // session-once-shown pattern) that actually decides whether to show
      // it, not this query param alone, so refreshing/revisiting never
      // repeats it.
      const timer = setTimeout(() => {
        router.replace(`/profile/events/${state.eventId}?welcome=1`);
      }, 900);
      return () => clearTimeout(timer);
    }
  }, [state, router]);

  return (
    <section className="page-hero" style={{ padding: '150px 0 120px', minHeight: '70vh' }}>
      <div className="hero__blob hero__blob--1"></div>
      <div className="container" style={{ maxWidth: 480 }}>
        <div className="ws-event-card" style={{ padding: 36, textAlign: 'center' }}>
          {state.status === 'loading' && (
            <>
              <div className="ws-skeleton" style={{ height: 60, marginBottom: 18 }} />
              <p className="ws-empty__text">
                <T ru="Открываем ваше пространство…" kz="Кеңістігіңіз ашылуда…" en="Opening your workspace…" />
              </p>
            </>
          )}

          {state.status === 'success' && (
            <>
              <span style={{ fontSize: 40 }}>✨</span>
              <h1 style={{ fontFamily: 'var(--font-playfair), serif', fontSize: 24, margin: '18px 0 10px' }}>
                <T ru="Готово!" kz="Дайын!" en="All set!" />
              </h1>
              <p className="ws-empty__text">
                <T ru="Открываем «Мой той»…" kz="«Менің тойым» ашылуда…" en="Opening «Мой той»…" />
              </p>
            </>
          )}

          {state.status === 'used' && (
            <>
              <span className="ws-empty__icon">🔓</span>
              <h2 className="ws-empty__title"><T ru="Ссылка уже использована" kz="Сілтеме бұрын қолданылған" en="This link was already used" /></h2>
              <p className="ws-empty__text">
                <T
                  ru="Похоже, пространство уже открывали раньше. Войдите в свой аккаунт, чтобы продолжить."
                  kz="Бұл кеңістік бұрын ашылған сияқты. Жалғастыру үшін аккаунтыңызға кіріңіз."
                  en="It looks like this workspace was already opened before. Log in to continue."
                />
              </p>
              <Link href="/login" className="btn btn--outline"><T ru="Войти" kz="Кіру" en="Log in" /></Link>
            </>
          )}

          {state.status === 'expired' && (
            <>
              <span className="ws-empty__icon">⏳</span>
              <h2 className="ws-empty__title"><T ru="Ссылка больше не активна" kz="Сілтеме енді белсенді емес" en="This link has expired" /></h2>
              <p className="ws-empty__text">
                <T
                  ru="Срок действия ссылки истёк. Оставьте новую заявку на сайте, или войдите, если уже знаете свои данные для входа."
                  kz="Сілтеменің мерзімі аяқталды. Сайтта жаңа өтінім қалдырыңыз немесе кіру деректеріңіз болса, кіріңіз."
                  en="This link has expired. Submit a new request on the site, or log in if you already know your credentials."
                />
              </p>
              <Link href="/" className="btn btn--outline"><T ru="На главную" kz="Басты бетке" en="Go home" /></Link>
            </>
          )}

          {state.status === 'invalid' && (
            <>
              <span className="ws-empty__icon">🚫</span>
              <h2 className="ws-empty__title"><T ru="Ссылка недействительна" kz="Сілтеме жарамсыз" en="Invalid link" /></h2>
              <p className="ws-empty__text">
                <T ru="Проверьте, что ссылка скопирована полностью." kz="Сілтеменің толық көшірілгенін тексеріңіз." en="Check that the link was copied in full." />
              </p>
              <Link href="/" className="btn btn--outline"><T ru="На главную" kz="Басты бетке" en="Go home" /></Link>
            </>
          )}
        </div>
      </div>
    </section>
  );
}
