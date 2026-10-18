import '../../../state/locale_provider.dart';

/// Russian plural form for [n]: one (1, 21), few (2–4, 22–24), many.
String _ru(int n, String one, String few, String many) {
  final mod10 = n % 10, mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return one;
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return few;
  return many;
}

String servicesCountLabel(AppLocale locale, int n) => t(
  locale,
  ru: '$n ${_ru(n, 'услуга', 'услуги', 'услуг')}',
  kz: '$n қызмет',
  en: n == 1 ? '1 service' : '$n services',
);

String bookingsCountLabel(AppLocale locale, int n) => t(
  locale,
  ru: '$n ${_ru(n, 'заявка', 'заявки', 'заявок')}',
  kz: '$n өтінім',
  en: n == 1 ? '1 request' : '$n requests',
);

String experienceLabel(AppLocale locale, int years) => t(
  locale,
  ru: 'опыт $years ${_ru(years, 'год', 'года', 'лет')}',
  kz: 'тәжірибе $years жыл',
  en: years == 1 ? '1 year of experience' : '$years years of experience',
);

/// Provider profile status as shown to its owner.
String providerStatusLabel(AppLocale locale, String status) {
  switch (status) {
    case 'active':
      return t(locale, ru: 'Активен', kz: 'Белсенді', en: 'Active');
    case 'pending':
      return t(
        locale,
        ru: 'На проверке',
        kz: 'Тексерілуде',
        en: 'Under review',
      );
    case 'draft':
      return t(locale, ru: 'Черновик', kz: 'Жоба', en: 'Draft');
    case 'rejected':
      return t(locale, ru: 'Отклонён', kz: 'Қабылданбады', en: 'Rejected');
    case 'suspended':
      return t(locale, ru: 'Приостановлен', kz: 'Тоқтатылған', en: 'Suspended');
    default:
      return status;
  }
}

/// Booking request status (backend: new / contacted / confirmed /
/// cancelled).
String bookingStatusLabel(AppLocale locale, String status) {
  switch (status) {
    case 'new':
      return t(locale, ru: 'Новая', kz: 'Жаңа', en: 'New');
    case 'contacted':
      return t(locale, ru: 'Связались', kz: 'Хабарласты', en: 'Contacted');
    case 'confirmed':
      return t(locale, ru: 'Подтверждена', kz: 'Расталды', en: 'Confirmed');
    case 'cancelled':
      return t(locale, ru: 'Отменена', kz: 'Бас тартылды', en: 'Cancelled');
    default:
      return status;
  }
}

/// dd.MM.yyyy — numeric on purpose, so it needs no intl locale data and
/// reads the same in every language.
String formatShortDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

String formatShortDateTime(DateTime d) =>
    '${formatShortDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
