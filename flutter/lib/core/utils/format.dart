import 'package:intl/intl.dart';

/// Same output as the site's formatPrice() (frontend/src/lib/format.js):
/// grouped thousands with a space, plus the tenge sign — e.g. "250 000 ₸".
final _priceFormat = NumberFormat.decimalPattern('ru');

String formatPrice(int amount) => '${_priceFormat.format(amount)} ₸';

/// Same output as the site's stats block (toLocaleString('ru-RU') + "+"),
/// e.g. "15 000+".
String formatStatValue(int amount) => '${_priceFormat.format(amount)}+';
