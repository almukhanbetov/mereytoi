'use client';

import { T } from '@/context/AppProviders';
import { listingWhatsAppHref } from '@/lib/phone';
import { adPromotionFor, recordPromotionEvent } from '@/lib/promotionApi';

// «Написать в WhatsApp» — where «Спросить менеджера» used to be: WhatsApp of
// this listing's own provider with a prepared message the visitor still
// sends themselves. Not rendered when that provider has no WhatsApp.
export default function ListingWhatsAppButton({ listing, lang }) {
  const href = listingWhatsAppHref(listing, lang);
  if (!href) return null;
  return (
    <a
      className="btn btn--outline"
      href={href}
      target="_blank"
      rel="noopener noreferrer"
      onClick={() => recordPromotionEvent(adPromotionFor(listing.id), 'whatsapp')}
    >
      <T ru="Написать в WhatsApp" kz="WhatsApp-қа жазу" en="Message on WhatsApp" />
    </a>
  );
}
