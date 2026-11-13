'use client';

import { T } from '@/context/AppProviders';
import { listingCallHref, listingWhatsAppHref } from '@/lib/phone';
import { adPromotionFor, recordPromotionEvent } from '@/lib/promotionApi';

const PHONE_PATH =
  'M6.62 10.79c1.44 2.83 3.76 5.14 6.59 6.59l2.2-2.2c.27-.27.67-.36 1.02-.24 1.12.37 2.33.57 3.57.57.55 0 1 .45 1 1V20c0 .55-.45 1-1 1-9.39 0-17-7.61-17-17 0-.55.45-1 1-1h3.5c.55 0 1 .45 1 1 0 1.25.2 2.45.57 3.57.11.35.03.74-.25 1.02l-2.2 2.2z';

function PhoneIcon() {
  return (
    <svg className="listing-contact__icon" viewBox="0 0 24 24" width="19" height="19" aria-hidden="true">
      <path d={PHONE_PATH} fill="currentColor" />
    </svg>
  );
}

// WhatsApp-style glyph: a speech-bubble ring with a tail and a handset inside
// (the same shape the app paints).
function WhatsAppIcon() {
  return (
    <svg className="listing-contact__icon" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true">
      <path
        d="M7.94 20.7 A9.6 9.6 0 1 0 3.3 16.06"
        fill="none" stroke="currentColor" strokeWidth="2.1" strokeLinecap="round"
      />
      <path d="M7.94 20.7 L1.2 22.8 L3.3 16.06 Z" fill="currentColor" />
      <path d={PHONE_PATH} fill="currentColor" transform="translate(6.5 6.5) scale(0.46)" />
    </svg>
  );
}

// «Позвонить» + «WhatsApp» of this listing's own provider — where
// «Спросить менеджера» used to be. Each button appears only when that
// provider has that contact; nothing renders without either. Never
// support's or another provider's number.
export default function ListingContactButtons({ listing, lang }) {
  const callHref = listingCallHref(listing);
  const waHref = listingWhatsAppHref(listing, lang);
  if (!callHref && !waHref) return null;
  const both = Boolean(callHref && waHref);
  const record = (kind) => recordPromotionEvent(adPromotionFor(listing.id), kind);
  return (
    <div className="listing-contacts">
      {callHref && (
        <a
          className="btn listing-contact listing-contact--call"
          href={callHref}
          onClick={() => record('call')}
        >
          <PhoneIcon />
          <span className="listing-contact__label">
            <T ru="Позвонить" kz="Қоңырау шалу" en="Call" />
          </span>
        </a>
      )}
      {waHref && (
        <a
          className="btn listing-contact listing-contact--whatsapp"
          href={waHref}
          target="_blank"
          rel="noopener noreferrer"
          onClick={() => record('whatsapp')}
        >
          <WhatsAppIcon />
          <span className="listing-contact__label">
            {both
              ? 'WhatsApp'
              : <T ru="Написать в WhatsApp" kz="WhatsApp-қа жазу" en="Message on WhatsApp" />}
          </span>
        </a>
      )}
    </div>
  );
}
