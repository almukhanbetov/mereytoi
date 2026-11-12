import 'dart:io' show SocketException;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:mereytoi_app/core/network/api_client.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/models/category.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/models/promotion.dart';
import 'package:mereytoi_app/screens/profile/provider/my_services_screen.dart';
import 'package:mereytoi_app/screens/profile/provider/promotion_screen.dart';
import 'package:mereytoi_app/screens/services/services_screen.dart';
import 'package:mereytoi_app/services/promotion_service.dart';
import 'package:mereytoi_app/services/store_purchase_service.dart';
import 'package:mereytoi_app/state/categories_provider.dart';
import 'package:mereytoi_app/state/listings_provider.dart';
import 'package:mereytoi_app/state/locale_provider.dart' show AppLocale;
import 'package:mereytoi_app/state/promotion_provider.dart';
import 'package:mereytoi_app/state/providers.dart';
import 'package:mereytoi_app/widgets/promotion/ad_label.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

Listing _listing(int id, {bool promoted = false, int? promotionId}) =>
    Listing.fromJson({
      ..._json(id),
      'promoted': promoted,
      'promotion_id': ?promotionId,
    });

Map<String, dynamic> _json(int id) => {
  'id': id,
  'category_id': 1,
  'name_ru': 'Услуга $id',
  'name_kz': 'Қызмет $id',
  'description_ru': '',
  'description_kz': '',
  'city': 'Алматы',
  'phone': '',
  'price': 10000,
  'min_guests': 0,
  'max_guests': 0,
  'rating': 0,
  'emoji': '',
  'color_from': '',
  'color_to': '',
  'image_urls': <String>[],
  'is_active': true,
};

/// Serves feed pages from a fixed list and a fixed promotion status.
class _FakePromotions extends PromotionService {
  _FakePromotions({this.pages = const [], this.status})
    : super(ApiClient.test(tokenProvider: () async => null));

  final List<CatalogPage> pages;
  final PromotionStatus? status;
  final List<(int, String)> events = [];
  final List<String?> cursors = [];

  @override
  Future<CatalogPage> fetchFeed({
    String? categorySlug,
    String? search,
    int? cityId,
    String? cursor,
    int limit = 20,
  }) async {
    cursors.add(cursor);
    final i = cursor == null ? 0 : int.parse(cursor);
    return pages[i];
  }

  @override
  Future<PromotionStatus> fetchStatus(int listingId) async => status!;

  @override
  Future<void> recordEvent(int promotionId, String kind) async {
    events.add((promotionId, kind));
  }
}

/// Fails like a dropped connection until [online] says otherwise.
class _FlakyPromotions extends PromotionService {
  _FlakyPromotions(this.online, this.page)
    : super(ApiClient.test(tokenProvider: () async => null));

  final bool Function() online;
  final CatalogPage page;

  @override
  Future<CatalogPage> fetchFeed({
    String? categorySlug,
    String? search,
    int? cityId,
    String? cursor,
    int limit = 20,
  }) async {
    if (!online()) throw const SocketException('offline');
    return page;
  }

  @override
  Future<void> recordEvent(int promotionId, String kind) async {}
}

PromotionStatus _status({
  bool canPurchase = true,
  String blocked = '',
  Map<String, dynamic>? running,
  List<Map<String, dynamic>> history = const [],
}) => PromotionStatus.fromJson({
  'listing_id': 1,
  'package': {'duration_days': 7, 'auto_renew': false, 'price_kzt': 2500},
  'channels': {
    'google': {'available': true, 'product_id': 'promo_7d'},
    'apple': {'available': false, 'reason': 'store_not_configured'},
    'web': {'available': false, 'reason': 'web_payment_not_available'},
  },
  'can_purchase': canPurchase,
  'blocked_reason': blocked,
  'running': running,
  'history': [?running, ...history],
});

Map<String, dynamic> _period({
  required bool running,
  String status = 'active',
  int impressions = 0,
}) => {
  'id': running ? 1 : 2,
  'status': status,
  'running': running,
  'channel': 'google',
  'starts_at': '2026-11-01T10:00:00Z',
  'ends_at': '2026-11-08T10:00:00Z',
  'stats': {
    'impressions': impressions,
    'clicks': 3,
    'chats': 2,
    'calls': 1,
    'whatsapp': 4,
  },
};

/// A store that has the product; buying is never reached in these tests.
class _FakeStore extends StorePurchaseController {
  _FakeStore(super.ref, this._product);

  final ProductDetails _product;
  final List<String> asked = [];

  @override
  void start() {}

  @override
  Future<ProductDetails?> product(String productId) async {
    asked.add(productId);
    return _product.id == productId ? _product : null;
  }
}

void setScreen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  Future<_FakePromotions> pumpCatalog(
    WidgetTester tester,
    List<CatalogPage> pages,
  ) async {
    setScreen(tester, const Size(390, 900));
    final fake = _FakePromotions(pages: pages);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          promotionServiceProvider.overrideWithValue(fake),
          categoriesProvider.overrideWith(
            (ref) => Future.value(const <Category>[]),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const ServicesScreen(initialCategorySlug: 'hosts'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  testWidgets(
    'after a failed connection, Retry restores categories and cards',
    (tester) async {
      setScreen(tester, const Size(390, 900));
      var online = false;
      final fake = _FlakyPromotions(
        () => online,
        CatalogPage(
          items: [_listing(1), _listing(2)],
          total: 2,
          nextCursor: null,
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            promotionServiceProvider.overrideWithValue(fake),
            categoriesProvider.overrideWith((ref) async {
              if (!online) throw const SocketException('offline');
              return [
                Category.fromJson({
                  'id': 1,
                  'slug': 'hosts',
                  'name_ru': 'Ведущие',
                  'name_kz': 'Жүргізушілер',
                  'position': 0,
                }),
              ];
            }),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const ServicesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // An error with Retry, never an empty catalog.
      expect(find.text('Повторить'), findsOneWidget);
      expect(find.text('Ведущие'), findsNothing);

      online = true;
      await tester.tap(find.text('Повторить'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.text('Ведущие'), findsOneWidget);
      expect(find.text('Найдено: 2'), findsOneWidget);
      expect(find.byKey(const ValueKey('service-grid-1')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('only the ad card is labelled «Реклама»', (tester) async {
    await pumpCatalog(tester, [
      CatalogPage(
        items: [
          _listing(1),
          _listing(2, promoted: true, promotionId: 77),
          _listing(3),
        ],
        total: 3,
        nextCursor: null,
      ),
    ]);
    expect(find.byType(AdLabel), findsOneWidget);
    expect(find.text('Реклама'), findsOneWidget);
    final label = tester.getRect(find.byType(AdLabel));
    final card = tester.getRect(find.byKey(const ValueKey('service-grid-2')));
    expect(card.contains(label.center), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an impression counts only after the ad was on screen', (
    tester,
  ) async {
    final fake = await pumpCatalog(tester, [
      CatalogPage(
        items: [_listing(1), _listing(2, promoted: true, promotionId: 77)],
        total: 2,
        nextCursor: null,
      ),
    ]);
    expect(fake.events, isEmpty);
    await tester.pump(const Duration(milliseconds: 1200));
    expect(fake.events, [(77, 'impression')]);
    // Still on screen: no second impression from this session.
    await tester.pump(const Duration(seconds: 3));
    expect(fake.events, [(77, 'impression')]);
  });

  testWidgets('pages append without repeating a listing', (tester) async {
    final fake = await pumpCatalog(tester, [
      CatalogPage(
        items: [for (var i = 1; i <= 6; i++) _listing(i)],
        total: 9,
        nextCursor: '1',
      ),
      CatalogPage(
        items: [_listing(6), _listing(7), _listing(8), _listing(9)],
        total: 9,
        nextCursor: null,
      ),
    ]);
    // Building the cards near the end loads the next page.
    await tester.pumpAndSettle();
    expect(fake.cursors, [null, '1']);
    expect(find.text('Найдено: 9'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('service-grid-9')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    // Listing 6 came again on page two: shown once.
    expect(find.byKey(const ValueKey('service-grid-6')), findsOneWidget);
    // Let the cards' entrance animations finish.
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  test(
    'ad clicks and contacts are attributed only to listings opened from an ad',
    () async {
      final fake = _FakePromotions();
      final container = ProviderContainer(
        overrides: [promotionServiceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);
      final tracker = container.read(adTrackerProvider);

      tracker.contact(5, 'call'); // opened normally: not counted
      tracker.opened(_listing(5)); // a regular card: not counted
      tracker.opened(_listing(6, promoted: true, promotionId: 9));
      tracker.contact(6, 'whatsapp');
      tracker.contact(6, 'chat');
      tracker.impression(9);
      tracker.impression(9);
      await Future<void>.delayed(Duration.zero);
      expect(fake.events, [
        (9, 'click'),
        (9, 'whatsapp'),
        (9, 'chat'),
        (9, 'impression'),
      ]);
    },
  );

  testWidgets('«Продвигать» is offered to the owner only', (tester) async {
    setScreen(tester, const Size(390, 900));
    Listing mine(int id, String role) =>
        Listing.fromJson({..._json(id), 'role': role});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myListingsProvider.overrideWith(
            (ref) => Future.value([mine(1, 'owner'), mine(2, 'manager')]),
          ),
          categoriesProvider.overrideWith(
            (ref) => Future.value(const <Category>[]),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const MyServicesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('service-promote-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('service-promote-2')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  Future<void> pumpPromotion(
    WidgetTester tester,
    PromotionStatus status, {
    AppLocale locale = AppLocale.ru,
    ThemeData? theme,
    Size size = const Size(390, 900),
  }) async {
    setScreen(tester, size);
    SharedPreferences.setMockInitialValues({'app_locale_v1': locale.name});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          promotionServiceProvider.overrideWithValue(
            _FakePromotions(status: status),
          ),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.light,
          home: PromotionScreen(listing: _listing(1)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('terms, price and duration are shown before paying', (
    tester,
  ) async {
    await pumpPromotion(tester, _status());
    expect(find.text('Пакет «7 дней»'), findsOneWidget);
    // The admin price (2 500 ₸) never stands in for the store's price:
    // without a store product there is no price, only an explanation.
    expect(find.byKey(const ValueKey('promotion-price')), findsNothing);
    expect(
      find.byKey(const ValueKey('promotion-price-pending')),
      findsOneWidget,
    );
    expect(find.textContaining(RegExp(r'2\s500')), findsNothing);
    expect(find.text('Без автопродления'), findsOneWidget);
    expect(find.text('Рейтинг, отзывы и значки не меняются'), findsOneWidget);
    // No store on the test host: buying is unavailable, with a reason —
    // never a fake success.
    final button = tester.widget<ElevatedButton>(
      find.byKey(const ValueKey('promotion-buy')),
    );
    expect(button.onPressed, isNull);
    expect(find.byKey(const ValueKey('promotion-note')), findsOneWidget);
  });

  testWidgets('the price shown is the store product\'s, with its currency', (
    tester,
  ) async {
    setScreen(tester, const Size(390, 900));
    late final _FakeStore store;
    final product = ProductDetails(
      id: 'promo_7d',
      title: '7 days',
      description: '',
      price: '\$4.99',
      rawPrice: 4.99,
      currencyCode: 'USD',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          promotionServiceProvider.overrideWithValue(
            _FakePromotions(status: _status()),
          ),
          storeChannelProvider.overrideWithValue('google'),
          storePurchaseProvider.overrideWith(
            (ref) => store = _FakeStore(ref, product),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: PromotionScreen(listing: _listing(1)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(store.asked, ['promo_7d']);
    expect(find.text('\$4.99'), findsOneWidget);
    expect(find.text('Продвигать за \$4.99'), findsOneWidget);
    // The admin's 2 500 ₸ is nowhere on screen.
    expect(find.textContaining(RegExp(r'2\s500')), findsNothing);
    final button = tester.widget<ElevatedButton>(
      find.byKey(const ValueKey('promotion-buy')),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('a manager sees status but only the owner can pay', (
    tester,
  ) async {
    await pumpPromotion(
      tester,
      _status(canPurchase: false, blocked: 'not_owner'),
    );
    expect(
      find.text('Оплатить продвижение может только владелец карточки.'),
      findsOneWidget,
    );
  });

  testWidgets('running: end date and statistics, taps not called orders', (
    tester,
  ) async {
    await pumpPromotion(
      tester,
      _status(
        canPurchase: false,
        blocked: 'already_running',
        running: _period(running: true, impressions: 1234),
        history: [_period(running: false, status: 'refunded')],
      ),
    );
    expect(find.byKey(const ValueKey('promotion-running')), findsOneWidget);
    expect(find.textContaining('Продвигается до 08.11.2026'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^1\s234$')), findsOneWidget);
    expect(find.text('Показы'), findsNWidgets(2));
    expect(find.textContaining('не подтверждённые заказы'), findsNWidgets(2));
    expect(find.textContaining('Возврат оплаты'), findsOneWidget);
    expect(find.byKey(const ValueKey('promotion-buy')), findsNothing);
  });

  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      for (final width in [320.0, 390.0, 430.0]) {
        testWidgets(
          'no overflow ${locale.name} · ${dark ? 'dark' : 'light'} · ${width.toInt()}',
          (tester) async {
            await pumpPromotion(
              tester,
              _status(
                running: _period(running: true, impressions: 98765),
                history: [_period(running: false)],
              ),
              locale: locale,
              theme: dark ? AppTheme.dark : AppTheme.light,
              size: Size(width, 760),
            );
            expect(tester.takeException(), isNull);
            await tester.drag(find.byType(ListView), const Offset(0, -2000));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
