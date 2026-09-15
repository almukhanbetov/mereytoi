import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/utils/format.dart';
import '../domain/pdf/pdf_booking_lines.dart';

/// Flutter's functional equivalent of `frontend/src/lib/pdf.js`'s
/// `downloadOfferPdf` (jsPDF + html2canvas rasterizing a styled HTML block)
/// — there is no backend PDF endpoint (confirmed by grep across
/// backend/internal/handlers and routes.go), so this stays entirely
/// client-side here too, just built natively with `pdf`/`printing` instead
/// of a raster hack. Content is deliberately richer than web's own PDF
/// (hall/menu/extras/booking ref — see `pdf_booking_lines.dart`'s own doc
/// comment), since that data already exists on a confirmed [Booking] and
/// the brief explicitly asks for it.
class PdfService {
  const PdfService();

  Future<pw.Document> buildDocument(PdfBookingData data) async {
    final regular = await PdfGoogleFonts.notoSansRegular();
    final bold = await PdfGoogleFonts.notoSansBold();
    final theme = pw.ThemeData.withFont(base: regular, bold: bold);

    final doc = pw.Document(theme: theme);
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'MEREYTOI',
              style: pw.TextStyle(
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              data.createdAt != null ? formatMenuDate(data.createdAt!) : '',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 16),
            if (data.publicRef.isNotEmpty)
              pw.Text(
                'Номер заявки: ${data.publicRef}',
                style: const pw.TextStyle(fontSize: 11),
              ),
            if (data.customerName.isNotEmpty || data.customerPhone.isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 4),
                child: pw.Text(
                  [
                    if (data.customerName.isNotEmpty) data.customerName,
                    if (data.customerPhone.isNotEmpty) data.customerPhone,
                  ].join(' · '),
                  style: const pw.TextStyle(fontSize: 11),
                ),
              ),
            pw.SizedBox(height: 20),
            pw.Divider(color: PdfColors.grey400),
            for (final line in data.lines) _buildLine(line),
            pw.Divider(color: PdfColors.grey700, thickness: 1),
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Итого',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  formatPrice(data.total),
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 24),
            pw.Text(
              'mereytoi.kz',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
          ],
        ),
      ),
    );
    return doc;
  }

  pw.Widget _buildLine(PdfBookingLine line) {
    final details = <String>[
      if (line.hallName != null && line.hallName!.isNotEmpty)
        'Зал: ${line.hallName}',
      if (line.menuName != null && line.menuName!.isNotEmpty)
        'Меню: ${line.menuName}',
      if (line.guests != null && line.pricePerGuest != null)
        '${line.guests} чел. × ${formatPrice(line.pricePerGuest!)}',
    ];
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                child: pw.Text(
                  line.title,
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.Text(formatPrice(line.totalPrice)),
            ],
          ),
          for (final detail in details)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 2),
              child: pw.Text(
                detail,
                style: const pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.grey700,
                ),
              ),
            ),
          if (line.extraTitles.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 2),
              child: pw.Text(
                '+ ${line.extraTitles.join(', ')}',
                style: const pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.grey700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _fileName(PdfBookingData data) => data.publicRef.isNotEmpty
      ? 'mereytoi-${data.publicRef}.pdf'
      : 'mereytoi-offer.pdf';

  /// "Open PDF" — the platform print/preview sheet, which itself also
  /// offers Save-to-Files/Print, without this app needing any storage
  /// permission of its own.
  Future<void> open(PdfBookingData data) async {
    final doc = await buildDocument(data);
    final bytes = await doc.save();
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: _fileName(data),
    );
  }

  /// "Share PDF" — the native share sheet (WhatsApp/Telegram/Files/etc.),
  /// the same one `url_launcher`-based sharing elsewhere in this app
  /// leaves to the OS rather than this app picking a destination itself.
  Future<void> share(PdfBookingData data) async {
    final doc = await buildDocument(data);
    final bytes = await doc.save();
    await Printing.sharePdf(bytes: bytes, filename: _fileName(data));
  }
}
