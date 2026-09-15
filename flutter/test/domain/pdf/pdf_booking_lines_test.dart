import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/domain/pdf/pdf_booking_lines.dart';
import 'package:mereytoi_app/models/booking.dart';

void main() {
  group('17. PDF data mapping — buildPdfLines/pdfDataFromBooking', () {
    test('an ordinary service line carries no hall/menu/guests detail', () {
      final item = BookingItem(
        listingId: 5,
        name: 'Ведущий',
        category: 'Ведущие',
        guests: 0,
        unitPrice: 250000,
        totalPrice: 250000,
      );
      final lines = buildPdfLines([item]);
      expect(lines, hasLength(1));
      expect(lines.single.title, 'Ведущий');
      expect(lines.single.hallName, isNull);
      expect(lines.single.menuName, isNull);
      expect(lines.single.guests, isNull);
      expect(lines.single.totalPrice, 250000);
    });

    test(
      'a restaurant variant line carries hall/menu/guests/price-per-guest/extras',
      () {
        final item = BookingItem(
          listingId: 42,
          name: 'Sultan Palace · Банкетное меню №1',
          category: 'Рестораны',
          guests: 100,
          unitPrice: 25000,
          totalPrice: 2620000,
          hallId: 1,
          hallName: 'Sultan Hall',
          menuId: 2,
          menuName: 'Банкетное меню №1',
          menuPricePerGuest: 25000,
          selectedExtras: const [
            BookingItemExtra(
              title: 'Детский стол',
              price: 12000,
              unit: 'per_guest',
            ),
          ],
          estimatedTotal: 2620000,
        );
        final lines = buildPdfLines([item]);
        final line = lines.single;
        expect(line.hallName, 'Sultan Hall');
        expect(line.menuName, 'Банкетное меню №1');
        expect(line.guests, 100);
        expect(line.pricePerGuest, 25000);
        expect(line.extraTitles, ['Детский стол']);
        expect(line.totalPrice, 2620000);
      },
    );

    test(
      'pdfDataFromBooking carries booking identity/contact/total straight through',
      () {
        final booking = Booking(
          id: 1,
          publicRef: 'abc123',
          name: 'Айгерим',
          phone: '+77001234567',
          message: '',
          items: const [],
          total: 500000,
          status: 'new',
          createdAt: DateTime.utc(2026, 3, 1),
        );
        final data = pdfDataFromBooking(booking);
        expect(data.publicRef, 'abc123');
        expect(data.customerName, 'Айгерим');
        expect(data.customerPhone, '+77001234567');
        expect(data.total, 500000);
        expect(data.createdAt, DateTime.utc(2026, 3, 1));
      },
    );
  });
}
