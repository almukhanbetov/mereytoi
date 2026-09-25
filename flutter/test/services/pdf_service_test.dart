import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/utils/format.dart';
import 'package:mereytoi_app/domain/pdf/pdf_booking_lines.dart';
import 'package:mereytoi_app/services/pdf_service.dart';
import 'package:mereytoi_app/state/locale_provider.dart';
import 'package:pdf/pdf.dart';

ByteData _fontBytes(String asset) =>
    ByteData.sublistView(File(asset).readAsBytesSync());

/// Hands PdfService the real bundled font files straight from disk, so
/// the test exercises exactly the bytes that ship in the APK.
class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => _fontBytes(key);
}

final _sample = PdfBookingData(
  publicRef: 'MT-2026-0042',
  createdAt: DateTime(2026, 9, 25),
  customerName: 'Әсем Құрманғалиева',
  customerPhone: '+7 701 000 00 00',
  lines: const [
    PdfBookingLine(
      title: 'Ресторан «Шаңырақ»',
      hallName: 'Үлкен зал',
      menuName: 'Қазақша мәзір',
      guests: 120,
      pricePerGuest: 15000,
      extraTitles: ['Һәм торт', 'Ірімшік'],
      totalPrice: 1800000,
    ),
  ],
  total: 1800000,
);

/// Every piece of text the PDF can print for [locale] with [_sample].
List<String> _allPrintedText(AppLocale locale) {
  final labels = PdfLabels(locale);
  final line = _sample.lines.single;
  return [
    'MEREYTOI',
    'mereytoi.kz',
    labels.date(_sample.createdAt!),
    '${labels.requestNumber}: ${_sample.publicRef}',
    _sample.customerName,
    _sample.customerPhone,
    line.title,
    '${labels.hall}: ${line.hallName}',
    '${labels.menu}: ${line.menuName}',
    labels.guestsTimesPrice(line.guests!, formatPrice(line.pricePerGuest!)),
    '+ ${line.extraTitles.join(', ')}',
    labels.total,
    formatPrice(_sample.total),
  ];
}

void main() {
  group('Этап 12C — PdfLabels RU/KZ/EN', () {
    test('Russian', () {
      const l = PdfLabels(AppLocale.ru);
      expect(l.requestNumber, 'Номер заявки');
      expect(l.total, 'Итого');
      expect(l.menu, 'Меню');
      expect(l.guestsTimesPrice(120, '15 000 ₸'), '120 чел. × 15 000 ₸');
      expect(l.date(DateTime(2026, 9, 25)), '25 сентября 2026');
    });

    test('Kazakh', () {
      const l = PdfLabels(AppLocale.kz);
      expect(l.requestNumber, 'Өтінім нөмірі');
      expect(l.total, 'Барлығы');
      expect(l.menu, 'Мәзір');
      expect(l.guestsTimesPrice(120, '15 000 ₸'), '120 адам × 15 000 ₸');
      expect(l.date(DateTime(2026, 9, 25)), '25 қыркүйек 2026 ж.');
    });

    test('English', () {
      const l = PdfLabels(AppLocale.en);
      expect(l.requestNumber, 'Request number');
      expect(l.total, 'Total');
      expect(l.hall, 'Hall');
      expect(l.guestsTimesPrice(120, '15 000 ₸'), '120 guests × 15 000 ₸');
      expect(l.date(DateTime(2026, 1, 3)), 'January 3, 2026');
    });

    test('every month name exists in every language', () {
      for (final locale in AppLocale.values) {
        for (var m = 1; m <= 12; m++) {
          expect(PdfLabels(locale).date(DateTime(2026, m, 1)), isNotEmpty);
        }
      }
    });
  });

  group('Этап 12C — bundled font covers everything the PDF prints', () {
    for (final asset in [pdfRegularFontAsset, pdfBoldFontAsset]) {
      test(
        '$asset has every glyph for RU/KZ/EN (incl. Ә Ғ Қ Ң Ө Ұ Ү Һ І, ₸)',
        () {
          final font = PdfTtfFont(PdfDocument(), _fontBytes(asset));
          const kazakh = 'ӘәҒғҚқҢңӨөҰұҮүҺһІі';
          final missing = <String>{};
          for (final text in [
            kazakh,
            '₸№«»×…',
            for (final locale in AppLocale.values) ..._allPrintedText(locale),
          ]) {
            for (final rune in text.runes) {
              // Spaces (incl. formatPrice's NBSP grouping) never need a glyph.
              if (String.fromCharCode(rune).trim().isEmpty) continue;
              if (!font.isRuneSupported(rune)) {
                missing.add(String.fromCharCode(rune));
              }
            }
          }
          expect(missing, isEmpty);
        // Guard against a vacuous pass: a glyph Noto Sans really lacks
        // (CJK lives in Noto Sans CJK) must be reported as unsupported.
        expect(font.isRuneSupported('中'.runes.first), isFalse);
        },
      );
    }
  });

  group('Этап 12C — PdfService builds a document in every language', () {
    for (final locale in AppLocale.values) {
      test(locale.name, () async {
        final doc = await const PdfService().buildDocument(
          _sample,
          locale,
          bundle: _DiskBundle(),
        );
        final bytes = await doc.save();
        expect(bytes.length, greaterThan(1000));
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      });
    }
  });
}
