/** Pushes whatsapp_click once per real click, right before the browser follows the link. */
export function trackWhatsAppClick() {
  if (typeof window === 'undefined') return;
  window.dataLayer = window.dataLayer || [];
  window.dataLayer.push({ event: 'whatsapp_click' });
}

function toWhatsAppDigits(phone) {
  const digits = (phone || '').replace(/\D/g, '');
  if (!digits) return '';
  if (digits.length === 11 && digits.startsWith('8')) return `7${digits.slice(1)}`;
  if (digits.length === 10) return `7${digits}`;
  return digits;
}

/** Builds a wa.me link with a pre-filled commercial-offer message for the cart's items. */
export function buildWhatsAppLink({ items, total, phone, lang, formatPrice }) {
  const header = lang === 'kz'
    ? '✨ MEREYTOI — Коммерциялық ұсыныс'
    : '✨ MEREYTOI — Коммерческое предложение';

  const lines = items.map((item, i) => {
    const detail = item.guests
      ? `${item.guests} ${lang === 'kz' ? 'адам' : 'чел.'} × ${formatPrice(item.unitPrice)} = ${formatPrice(item.totalPrice)}`
      : formatPrice(item.totalPrice);
    return `${i + 1}. ${item.name}\n   ${detail}`;
  });

  const totalLine = `${lang === 'kz' ? 'Барлығы' : 'Итого'}: ${formatPrice(total)}`;
  const text = [header, '', ...lines, '', totalLine, '', 'mereytoi.kz'].join('\n');

  const digits = toWhatsAppDigits(phone);
  const base = digits ? `https://wa.me/${digits}` : 'https://wa.me/';
  return `${base}?text=${encodeURIComponent(text)}`;
}
