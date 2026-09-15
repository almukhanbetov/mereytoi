import 'package:intl/intl.dart';

/// Same output as the site's formatPrice() (frontend/src/lib/format.js):
/// grouped thousands with a space, plus the tenge sign — e.g. "250 000 ₸".
final _priceFormat = NumberFormat.decimalPattern('ru');

String formatPrice(int amount) => '${_priceFormat.format(amount)} ₸';

/// Same output as the site's stats block (toLocaleString('ru-RU') + "+"),
/// e.g. "15 000+".
String formatStatValue(int amount) => '${_priceFormat.format(amount)}+';

/// Same output as RestaurantMenuDetail.jsx's `formatDate()` — always
/// `ru-RU`/`{day:'2-digit', month:'long', year:'numeric'}` regardless of the
/// app's own locale toggle, e.g. "10 сентября 2026". Spelled out by hand
/// (not `DateFormat(..., 'ru')`) so this doesn't depend on `intl`'s
/// locale-data being initialized at app startup — this app never otherwise
/// needs `initializeDateFormatting()`.
const _ruMonths = [
  'января',
  'февраля',
  'марта',
  'апреля',
  'мая',
  'июня',
  'июля',
  'августа',
  'сентября',
  'октября',
  'ноября',
  'декабря',
];

String formatMenuDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  return '$day ${_ruMonths[date.month - 1]} ${date.year}';
}
