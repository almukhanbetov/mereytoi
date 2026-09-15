import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/utils/format.dart';
import 'package:mereytoi_app/domain/manager_chat/manager_chat_context.dart';

void main() {
  group('restaurantContextText — exact port of FloatingManagerWidget.jsx', () {
    test(
      'no hall/menu at all — empty string (a plain service/event context)',
      () {
        const ctx = ManagerChatContext(
          eventId: 7,
          listingId: 5,
          listingName: 'Ведущий',
        );
        expect(restaurantContextText(ctx), '');
      },
    );

    test(
      'hall + menu + price + guests + total builds the full context line',
      () {
        const ctx = ManagerChatContext(
          listingId: 42,
          hallName: 'Sultan Hall',
          menuName: 'Банкетное меню №1',
          menuPricePerGuest: 25000,
          guestCount: 150,
          estimatedTotal: 3850000,
        );
        final text = restaurantContextText(ctx);
        expect(text, contains('Зал: Sultan Hall'));
        expect(text, contains('Меню: Банкетное меню №1'));
        // formatPrice() itself (not a hand-typed literal) — NumberFormat's
        // 'ru' thousands separator is a non-breaking space, not a plain one.
        expect(text, contains('${formatPrice(25000)}/чел.'));
        expect(text, contains('150 гостей'));
        expect(text, contains('≈${formatPrice(3850000)}'));
        expect(text, startsWith('Контекст: '));
        expect(text, endsWith('. '));
      },
    );

    test('menu without a price per guest omits the "/чел." price entirely', () {
      const ctx = ManagerChatContext(menuName: 'Меню', menuPricePerGuest: 0);
      expect(restaurantContextText(ctx), 'Контекст: Меню: Меню. ');
    });

    test('an event-only context (no hall/menu) is also empty', () {
      const ctx = ManagerChatContext(eventId: 7, eventTitle: 'Свадьба');
      expect(restaurantContextText(ctx), '');
    });
  });
}
