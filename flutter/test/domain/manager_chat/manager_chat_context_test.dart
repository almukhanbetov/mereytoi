import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/utils/format.dart';
import 'package:mereytoi_app/domain/manager_chat/manager_chat_context.dart';
import 'package:mereytoi_app/state/locale_provider.dart';

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
        expect(restaurantContextText(AppLocale.ru, ctx), '');
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
        final text = restaurantContextText(AppLocale.ru, ctx);
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

    test('the same context under AppLocale.en renders the English wording', () {
      const ctx = ManagerChatContext(
        listingId: 42,
        hallName: 'Sultan Hall',
        menuName: 'Wedding menu',
        menuPricePerGuest: 25000,
        guestCount: 150,
        estimatedTotal: 3850000,
      );
      final text = restaurantContextText(AppLocale.en, ctx);
      expect(text, contains('Hall: Sultan Hall'));
      expect(text, contains('Menu: Wedding menu'));
      expect(text, contains('${formatPrice(25000)}/guest'));
      expect(text, contains('150 guests'));
      expect(text, startsWith('Context: '));
    });

    test('menu without a price per guest omits the "/чел." price entirely', () {
      const ctx = ManagerChatContext(menuName: 'Меню', menuPricePerGuest: 0);
      expect(
        restaurantContextText(AppLocale.ru, ctx),
        'Контекст: Меню: Меню. ',
      );
    });

    test('an event-only context (no hall/menu) is also empty', () {
      const ctx = ManagerChatContext(eventId: 7, eventTitle: 'Свадьба');
      expect(restaurantContextText(AppLocale.ru, ctx), '');
    });
  });
}
