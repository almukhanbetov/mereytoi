import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/core/utils/phone.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/state/locale_provider.dart' show AppLocale;
import 'package:mereytoi_app/widgets/listing_hero_header.dart';

Listing _listing({
  String? whatsapp,
  String? providerPhone,
  String phone = '+7 777 000 00 00',
}) => Listing.fromJson({
  'id': 42,
  'category_id': 2,
  'name_ru': 'Ведущий Ерлан',
  'name_kz': 'Жүргізуші Ерлан',
  'city': 'Алматы',
  // The listing's own phone is never used for the WhatsApp button.
  'phone': phone,
  'is_active': true,
  'provider': {
    'id': 7,
    'display_name': 'Ерлан',
    'whatsapp': ?whatsapp,
    'phone': ?providerPhone,
  },
});

void main() {
  test('normalizePhone: the same rules as the server', () {
    const ok = {
      '': '',
      '  ': '',
      '+7 701 123 45 67': '+77011234567',
      '8 (701) 123-45-67': '+77011234567',
      '87011234567': '+77011234567',
      '77011234567': '+77011234567',
      '7011234567': '+77011234567',
      '+7-727-250-00-00': '+77272500000',
      '+998 90 123 45 67': '+998901234567',
      '+7 701 123 45 67': '+77011234567',
    };
    ok.forEach(
      (input, want) => expect(normalizePhone(input), want, reason: input),
    );
    for (final bad in [
      'abc',
      '+7 701 123',
      '+7701123456789',
      '12345',
      '8701123456',
      '+0123456789',
      '@whatsapp',
      '+77011234567+',
    ]) {
      expect(normalizePhone(bad), isNull, reason: bad);
    }
  });

  test(
    'the WhatsApp link goes to this listing\'s provider, with a prepared text',
    () {
      final uri = listingWhatsAppUri(
        _listing(whatsapp: '8 702 765 43 21'),
        AppLocale.ru,
      )!;
      expect(uri.host, 'wa.me');
      expect(uri.path, '/77027654321');
      final text = uri.queryParameters['text']!;
      expect(text, contains('«Ведущий Ерлан»'));
      expect(text, contains('https://mereytoi.kz/services/42'));
      expect(
        listingWhatsAppUri(
          _listing(whatsapp: '+77027654321'),
          AppLocale.kz,
        )!.queryParameters['text'],
        contains('«Жүргізуші Ерлан»'),
      );
    },
  );

  test(
    'no WhatsApp: no link — never support, the listing phone or another number',
    () {
      expect(listingWhatsAppUri(_listing(), AppLocale.ru), isNull);
      expect(listingWhatsAppUri(_listing(whatsapp: ''), AppLocale.ru), isNull);
      expect(
        listingWhatsAppUri(_listing(whatsapp: 'not a number'), AppLocale.ru),
        isNull,
      );
    },
  );

  Future<void> pumpButton(WidgetTester tester, Listing listing) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ListingWhatsAppButton(listing: listing, locale: AppLocale.ru),
          ),
        ),
      ),
    );
  }

  testWidgets('«Написать в WhatsApp» only with the provider\'s WhatsApp', (
    tester,
  ) async {
    await pumpButton(tester, _listing(whatsapp: '+77027654321'));
    expect(find.text('Написать в WhatsApp'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('listing-whatsapp'))).height,
      greaterThanOrEqualTo(48),
    );
    await pumpButton(tester, _listing());
    expect(find.text('Написать в WhatsApp'), findsNothing);
  });

  test('«Позвонить»: tel: of this listing\'s provider phone only', () {
    final uri = listingCallUri(_listing(providerPhone: '8 (702) 765-43-21'))!;
    expect(uri.scheme, 'tel');
    expect(uri.toString(), 'tel:+77027654321');
    // The listing's own phone (+7 777 …) and the WhatsApp number never stand
    // in for a missing provider phone.
    expect(listingCallUri(_listing(whatsapp: '+77027654321')), isNull);
    expect(listingCallUri(_listing(providerPhone: '')), isNull);
    expect(listingCallUri(_listing(providerPhone: 'call me')), isNull);
  });

  Future<void> pumpContacts(
    WidgetTester tester,
    Listing listing, {
    AppLocale locale = AppLocale.ru,
    double width = 390,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: theme ?? AppTheme.light,
          home: Scaffold(
            body: Padding(
              // The hero header's own horizontal padding.
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListingContactButtons(listing: listing, locale: locale),
            ),
          ),
        ),
      ),
    );
  }

  const call = ValueKey('listing-call');
  const whatsapp = ValueKey('listing-whatsapp');

  testWidgets('both contacts: two buttons in one row, same height', (
    tester,
  ) async {
    await pumpContacts(
      tester,
      _listing(providerPhone: '+77011234567', whatsapp: '+77027654321'),
    );
    expect(find.text('Позвонить'), findsOneWidget);
    expect(find.text('WhatsApp'), findsOneWidget);
    final a = tester.getRect(find.byKey(call));
    final b = tester.getRect(find.byKey(whatsapp));
    expect(a.height, greaterThanOrEqualTo(48));
    expect(a.height, b.height);
    expect(a.top, b.top);
    expect(a.width, closeTo(b.width, 0.5));
    expect(a.right, lessThan(b.left));
  });

  testWidgets('each button is independent', (tester) async {
    await pumpContacts(tester, _listing(providerPhone: '+77011234567'));
    expect(find.byKey(call), findsOneWidget);
    expect(find.byKey(whatsapp), findsNothing);

    await pumpContacts(tester, _listing(whatsapp: '+77027654321'));
    expect(find.byKey(call), findsNothing);
    expect(find.text('Написать в WhatsApp'), findsOneWidget);

    await pumpContacts(tester, _listing());
    expect(find.byKey(call), findsNothing);
    expect(find.byKey(whatsapp), findsNothing);
  });

  testWidgets('320dp, RU/KZ/EN, light and dark: no overflow', (tester) async {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      for (final locale in AppLocale.values) {
        await pumpContacts(
          tester,
          _listing(providerPhone: '+77011234567', whatsapp: '+77027654321'),
          locale: locale,
          width: 320,
          theme: theme,
        );
        expect(tester.takeException(), isNull, reason: '$locale');
        expect(
          tester.getSize(find.byKey(call)).height,
          greaterThanOrEqualTo(48),
        );
      }
    }
  });
}
