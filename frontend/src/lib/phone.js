// Phone/WhatsApp numbers in the international format the server stores
// (backend handlers/provider_contacts.go — the same rules): spaces, dashes,
// dots and brackets ignored; a local "8 7xx…", "7 7xx…" or a bare 10-digit
// "7xx…" number becomes "+7…"; another "+<code><number>" is kept.
// Returns "" for an empty value and null when it can't be a phone number.
export function normalizePhone(raw) {
  const s = (raw || '').trim();
  if (!s) return '';
  const plus = s.startsWith('+');
  let digits = '';
  for (let i = 0; i < s.length; i += 1) {
    const ch = s[i];
    if (ch >= '0' && ch <= '9') digits += ch;
    else if (ch === '+' && i === 0) continue;
    else if (!' -(). '.includes(ch)) return null;
  }
  if (plus) {
    if (digits.startsWith('7')) return digits.length === 11 ? `+${digits}` : null;
    if (digits.length < 8 || digits.length > 15 || digits.startsWith('0')) return null;
    return `+${digits}`;
  }
  if (digits.length === 11 && (digits[0] === '8' || digits[0] === '7')) return `+7${digits.slice(1)}`;
  if (digits.length === 10 && digits[0] === '7') return `+7${digits}`;
  return null;
}

// «Написать в WhatsApp» for a listing: wa.me to THIS listing's own provider
// with a prepared message the visitor sends themselves. null when that
// provider has no WhatsApp — never support's or anyone else's number.
export function listingWhatsAppHref(listing, lang) {
  const number = normalizePhone(listing?.provider?.whatsapp || '');
  if (!number) return null;
  const name = lang === 'kz' ? (listing.name_kz || listing.name_ru) : listing.name_ru;
  const url = `https://mereytoi.kz/services/${listing.id}`;
  const text = lang === 'kz'
    ? `Сәлеметсіз бе! MEREYTOI-дағы «${name}» бойынша жазып отырмын: ${url}`
    : `Здравствуйте! Пишу по поводу «${name}» на MEREYTOI: ${url}`;
  return `https://wa.me/${number.slice(1)}?text=${encodeURIComponent(text)}`;
}
