import '../../models/booking.dart';

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
