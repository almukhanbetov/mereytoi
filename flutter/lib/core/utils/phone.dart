import '../../models/listing.dart';
import '../../state/locale_provider.dart';

/// Brings a phone/WhatsApp number to the international format the server
/// stores (backend handlers/provider_contacts.go, the same rules): spaces,
/// dashes, dots and brackets ignored; a local "8 7xx…", "7 7xx…" or a bare
/// 10-digit "7xx…" number becomes "+7…"; another `+code number` is kept.
/// Returns "" for an empty input and null when it can't be a phone number.
String? normalizePhone(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return '';
  final plus = s.startsWith('+');
  final digits = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (RegExp(r'[0-9]').hasMatch(ch)) {
      digits.write(ch);
    } else if (ch == '+' && i == 0) {
      continue;
    } else if (!' -(). '.contains(ch)) {
      return null;
    }
  }
  final d = digits.toString();
  if (plus) {
    if (d.startsWith('7')) return d.length == 11 ? '+$d' : null;
    if (d.length < 8 || d.length > 15 || d.startsWith('0')) return null;
    return '+$d';
  }
  if (d.length == 11 && (d.startsWith('8') || d.startsWith('7'))) {
    return '+7${d.substring(1)}';
  }
  if (d.length == 10 && d.startsWith('7')) return '+7$d';
  return null;
}

/// «Написать в WhatsApp» for a listing: a wa.me link to **this listing's
/// own provider**, with a prepared message the user still sends themselves.
/// Null when that provider has no WhatsApp — never a fallback to support or
/// to any other number.
Uri? listingWhatsAppUri(Listing listing, AppLocale locale) {
  final raw = listing.provider?.whatsapp ?? '';
  final number = normalizePhone(raw);
  if (number == null || number.isEmpty) return null;
  final name = listing.name(locale);
  final url = 'https://mereytoi.kz/services/${listing.id}';
  final text = t(
    locale,
    ru: 'Здравствуйте! Пишу по поводу «$name» на MEREYTOI: $url',
    kz: 'Сәлеметсіз бе! MEREYTOI-дағы «$name» бойынша жазып отырмын: $url',
    en: 'Hello! I’m writing about “$name” on MEREYTOI: $url',
  );
  return Uri.https('wa.me', '/${number.substring(1)}', {'text': text});
}
