import 'package:url_launcher/url_launcher.dart';

import '../../models/cart_item.dart';
import '../../state/locale_provider.dart';
import 'format.dart';

/// Same normalization the site uses (frontend/src/lib/whatsapp.js's
/// toWhatsAppDigits): a local "8..." number becomes "7...", a bare 10-digit
/// number gets a leading 7, anything else is passed through as digits only.
String _toWhatsAppDigits(String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return '';
  if (digits.length == 11 && digits.startsWith('8')) return '7${digits.substring(1)}';
  if (digits.length == 10) return '7$digits';
  return digits;
}

/// Builds the same wa.me pre-filled commercial-offer message the site's
/// cart WhatsApp button sends (frontend/src/lib/whatsapp.js's
/// buildWhatsAppLink) — opens a chat to the phone number the customer
/// entered, with the cart contents as the message text.
String buildWhatsAppLink({required List<CartItem> items, required int total, required String phone, required AppLocale locale}) {
  final header = t(locale, ru: '✨ MEREYTOI — Коммерческое предложение', kz: '✨ MEREYTOI — Коммерциялық ұсыныс');

  final lines = <String>[];
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    final detail = item.guests > 0
        ? '${item.guests} ${t(locale, ru: "чел.", kz: "адам")} × ${formatPrice(item.unitPrice)} = ${formatPrice(item.totalPrice)}'
        : formatPrice(item.totalPrice);
    lines.add('${i + 1}. ${item.name}\n   $detail');
  }

  final totalLine = '${t(locale, ru: "Итого", kz: "Барлығы")}: ${formatPrice(total)}';
  final text = [header, '', ...lines, '', totalLine, '', 'mereytoi.kz'].join('\n');

  final digits = _toWhatsAppDigits(phone);
  final base = digits.isNotEmpty ? 'https://wa.me/$digits' : 'https://wa.me/';
  return '$base?text=${Uri.encodeComponent(text)}';
}

Future<bool> openWhatsApp(String link) {
  return launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
}
