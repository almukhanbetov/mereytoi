import '../../models/booking.dart';
import '../../state/locale_provider.dart';

/// One printable row of the PDF export — plain data, no `pw.Widget`
/// anywhere in this file, so the mapping from a [Booking]'s items to what
/// actually ends up on the page is unit-testable without rendering
/// anything. Richer than web's own `pdf.js` output (brief section 9 asks
/// for hall/menu/guests/extras — `frontend/src/lib/pdf.js` only ever shows
/// a flat name + guests×price line), which is a deliberate enhancement:
/// this data is genuinely available from the booking response, web's PDF
/// just never surfaced it.
class PdfBookingLine {
  const PdfBookingLine({
    required this.title,
    this.hallName,
    this.menuName,
    this.guests,
    this.pricePerGuest,
    this.extraTitles = const [],
    required this.totalPrice,
  });

  final String title;
  final String? hallName;
  final String? menuName;
  final int? guests;
  final int? pricePerGuest;
  final List<String> extraTitles;
  final int totalPrice;
}

/// The full, plain-data shape [PdfService] renders — booking identity,
/// customer contact, the line items, and the grand total. Never carries
/// any internal token (session/claim/etc.) — only what
/// `backend/internal/models/booking.go`'s own `Booking` already exposes.
class PdfBookingData {
  const PdfBookingData({
    required this.publicRef,
    required this.createdAt,
    required this.customerName,
    required this.customerPhone,
    required this.lines,
    required this.total,
  });

  final String publicRef;
  final DateTime? createdAt;
  final String customerName;
  final String customerPhone;
  final List<PdfBookingLine> lines;
  final int total;
}

/// Maps a confirmed [Booking] (the server's own echoed response — never
/// recomputed from local cart state) to the plain rows the PDF renders.
List<PdfBookingLine> buildPdfLines(List<BookingItem> items) {
  return items
      .map(
        (item) => PdfBookingLine(
          title: item.name,
          hallName: item.hallName,
          menuName: item.menuName,
          guests: item.guests > 0 ? item.guests : null,
          pricePerGuest: item.isRestaurantVariant
              ? (item.menuPricePerGuest ?? item.unitPrice)
              : (item.guests > 0 ? item.unitPrice : null),
          extraTitles: item.selectedExtras.map((e) => e.title).toList(),
          totalPrice: item.totalPrice,
        ),
      )
      .toList();
}

/// Builds the full [PdfBookingData] straight from a confirmed [Booking].
PdfBookingData pdfDataFromBooking(Booking booking) {
  return PdfBookingData(
    publicRef: booking.publicRef,
    createdAt: booking.createdAt,
    customerName: booking.name,
    customerPhone: booking.phone,
    lines: buildPdfLines(booking.items),
    total: booking.total,
  );
}

/// Этап 12C — every fixed string the PDF prints, in the viewer's current
/// app language (the PDF used to be Russian-only). Kept here as plain data,
/// like the lines themselves, so the RU/KZ/EN copy is unit-testable without
/// rendering a page. Line titles/hall/menu/extras stay exactly as the
/// booking stored them — they're the server's own names, not UI copy.
class PdfLabels {
  const PdfLabels(this.locale);

  final AppLocale locale;

  String get requestNumber =>
      t(locale, ru: 'Номер заявки', kz: 'Өтінім нөмірі', en: 'Request number');
  String get total => t(locale, ru: 'Итого', kz: 'Барлығы', en: 'Total');
  String get hall => t(locale, ru: 'Зал', kz: 'Зал', en: 'Hall');
  String get menu => t(locale, ru: 'Меню', kz: 'Мәзір', en: 'Menu');

  /// "120 чел. × 15 000 ₸" — the per-guest breakdown under a line.
  String guestsTimesPrice(int guests, String price) => t(
    locale,
    ru: '$guests чел. × $price',
    kz: '$guests адам × $price',
    en: '$guests guests × $price',
  );

  String date(DateTime date) {
    final months = switch (locale) {
      AppLocale.ru => _ruGenitiveMonths,
      AppLocale.kz => _kzMonths,
      AppLocale.en => _enMonths,
    };
    final month = months[date.month - 1];
    return switch (locale) {
      AppLocale.ru => '${date.day} $month ${date.year}',
      AppLocale.kz => '${date.day} $month ${date.year} ж.',
      AppLocale.en => '$month ${date.day}, ${date.year}',
    };
  }
}

const _ruGenitiveMonths = [
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня', //
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
];
const _kzMonths = [
  'қаңтар', 'ақпан', 'наурыз', 'сәуір', 'мамыр', 'маусым', //
  'шілде', 'тамыз', 'қыркүйек', 'қазан', 'қараша', 'желтоқсан',
];
const _enMonths = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];
