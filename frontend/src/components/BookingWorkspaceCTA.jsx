'use client';

import { useState } from 'react';
import Link from 'next/link';
import { T } from '@/context/AppProviders';
import { authApi } from '@/lib/authApi';

/** The one new piece of UI this stage adds — an *additive* extra block
 * under an existing booking success message, never a replacement for it.
 * Renders nothing at all when there's no `onboarding` object on the
 * booking response — which is always the case when
 * AUTO_ACCOUNT_FROM_BOOKING is off, or when the booking already had a
 * user/event attached, so every existing success screen is visually
 * identical to before unless this pipeline actually did something.
 *
 * The "Открыть мой той" CTA is a plain link to /claim/[token] (see that
 * page) rather than claiming inline here — one single place then owns the
 * whole claim→session→redirect→first-login-welcome sequence, whether it's
 * reached from this same-page button today or from a link delivered over
 * WhatsApp/Telegram (see backend/internal/claimdelivery — messenger
 * delivery replaced this pipeline's earlier SMS-based iteration entirely).
 *
 * `phone` is the raw phone the customer just typed into this same form —
 * only used locally, for the optional "Отправить ещё раз" resend call
 * (which always goes out over whichever channel is actually usable right
 * now — see ClaimResend's own doc comment on the backend, never a channel
 * picker here, since an anonymous visitor at this point can't yet know
 * whether Telegram is linked for them: that requires a session that only
 * exists after a first claim). */
export default function BookingWorkspaceCTA({ onboarding, phone }) {
  const [resendState, setResendState] = useState('idle'); // idle | sending | done

  if (!onboarding) return null;

  async function handleResend() {
    if (!phone || resendState !== 'idle') return;
    setResendState('sending');
    try {
      await authApi.claimResend(phone);
    } catch {
      // The endpoint itself never errors on a legitimate-shaped request
      // (brief section 12 — always the same neutral response); a network
      // failure here just leaves the customer able to try again.
    } finally {
      setResendState('done');
    }
  }

  // "Заявка добавлена в ваш кабинет MEREYTOI" — never "мы создали аккаунт"
  // for this branch: nothing was created here, an existing (real,
  // password-protected) account's phone just matched. "Открыть кабинет"
  // still routes through the normal login form (never an instant/auto
  // session — see onboarding.go's own doc comment on why an active
  // account never gets a claim link), with `next` so they land back in
  // their own event list right after.
  if (onboarding.status === 'existing_account') {
    return (
      <div className="booking-workspace-cta">
        <p className="booking-workspace-cta__text">
          <T
            ru="Заявка добавлена в ваш кабинет MEREYTOI."
            kz="Өтінім сіздің MEREYTOI кабинетіңізге қосылды."
          />
        </p>
        <Link href="/login?next=/profile" className="btn btn--outline btn--sm">
          <T ru="Открыть кабинет" kz="Кабинетті ашу" />
        </Link>
      </div>
    );
  }

  if ((onboarding.status === 'created_pending' || onboarding.status === 'pending_claim') && onboarding.claim_token) {
    // Slightly different opening line depending on whether this is a
    // brand-new workspace or one an earlier booking from the same
    // still-pending phone already prepared — "создано" only the first time.
    const intro = onboarding.status === 'created_pending'
      ? { ru: 'Для вас создано пространство «Мой той».', kz: '«Менің тойым» кеңістігі сіз үшін жасалды.' }
      : { ru: 'Для вас уже подготовлено пространство «Мой той».', kz: '«Менің тойым» кеңістігі сіз үшін дайын.' };

    return (
      <div className="booking-workspace-cta">
        <p className="booking-workspace-cta__text">
          <T ru={intro.ru} kz={intro.kz} />{' '}
          <T
            ru="В нём можно вместе с близкими выбирать услуги, обсуждать варианты, сравнивать цены и контролировать бюджет."
            kz="Онда жақындарыңызбен бірге қызметтерді таңдап, нұсқаларды талқылап, бағаларды салыстырып, бюджетті бақылай аласыз."
          />
        </p>

        {/* delivery_status is only ever present when CLAIM_DELIVERY_ENABLED
            is actually on AND some channel was actually usable for this
            user (see onboardingResult's own doc comment on the backend) —
            absent entirely means "no external delivery happened", and
            this block must say nothing about WhatsApp/Telegram at all in
            that case (brief section 8). */}
        {onboarding.delivery_status === 'sent' && onboarding.delivery_channel === 'whatsapp' && (
          <p className="booking-workspace-cta__text booking-workspace-cta__text--muted">
            <T ru="Ссылка на «Мой той» отправлена в WhatsApp." kz="«Менің тойым» сілтемесі WhatsApp-қа жіберілді." />
          </p>
        )}
        {onboarding.delivery_status === 'sent' && onboarding.delivery_channel === 'telegram' && (
          <p className="booking-workspace-cta__text booking-workspace-cta__text--muted">
            <T ru="Ссылка на «Мой той» отправлена в Telegram." kz="«Менің тойым» сілтемесі Telegram-ға жіберілді." />
          </p>
        )}

        <Link href={`/claim/${onboarding.claim_token}`} className="btn btn--gold btn--sm">
          <T ru="Открыть мой той" kz="Менің тойымды ашу" />
        </Link>

        {(onboarding.delivery_status === 'failed' || onboarding.delivery_status === 'skipped') && (
          resendState === 'done' ? (
            <p className="booking-workspace-cta__text booking-workspace-cta__text--muted">
              <T ru="Если ссылка не пришла в течение пары минут, свяжитесь с нами." kz="Сілтеме бірнеше минут ішінде келмесе, бізбен байланысыңыз." />
            </p>
          ) : (
            <button
              type="button"
              className="booking-workspace-cta__resend"
              onClick={handleResend}
              disabled={resendState === 'sending'}
            >
              <T ru="Отправить ссылку ещё раз" kz="Сілтемені қайта жіберу" />
            </button>
          )
        )}
      </div>
    );
  }

  return null;
}
