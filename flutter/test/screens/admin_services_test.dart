import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/network/api_client.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/models/category.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/screens/admin/admin_listing_form_screen.dart';
import 'package:mereytoi_app/screens/admin/admin_services_screen.dart';
import 'package:mereytoi_app/screens/profile/restaurant_admin/restaurant_manage_screen.dart';
import 'package:mereytoi_app/state/admin_providers.dart';
import 'package:mereytoi_app/state/categories_provider.dart';
import 'package:mereytoi_app/state/listings_provider.dart';
import 'package:mereytoi_app/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _venues = Category(
  id: 1,
  slug: 'venues',
  nameRu: 'Рестораны и локации',
  nameKz: 'Мейрамханалар',
  position: 1,
);
const _hosts = Category(
  id: 2,
  slug: 'hosts',
  nameRu: 'Ведущие',
  nameKz: 'Жүргізушілер',
  position: 2,
);

Map<String, dynamic> _json(
  int id,
  String name, {
  int category = 2,
  bool active = true,
  String? hiddenAt,
  String reason = '',
  String city = 'Алматы',
  String? owner,
}) => {
  'id': id,
  'category_id': category,
  'name_ru': name,
  'name_kz': '$name кз',
  'description_ru': 'Описание',
  'description_kz': 'Сипаттама',
  'city': city,
  'phone': '',
  'price': 50000,
  'min_guests': 0,
  'max_guests': 0,
  'rating': 4,
  'emoji': '🎤',
  'color_from': '#3a1420',
  'color_to': '#d4af6a',
  'image_urls': const <String>[],
  'video_urls': const <String>[],
  'is_active': active,
  'moderation_hidden_at': hiddenAt,
  'moderation_reason': reason,
  'price_type': 'fixed',
  if (owner != null) 'provider': {'id': 9, 'display_name': owner},
};

final _all = [
  Listing.fromJson(_json(10, 'Ерлан Ведущий', owner: 'Ерлан Events')),
  Listing.fromJson(_json(11, 'Снятый ведущий', active: false, city: 'Астана')),
  Listing.fromJson(
    _json(
      12,
      'Скрытый ведущий',
      hiddenAt: '2026-11-18T10:00:00Z',
      reason: 'Жалобы',
    ),
  ),
  Listing.fromJson(_json(13, 'Grand Hall', category: 1)),
  // As the admin list reports a listing whose owner is blocked.
  Listing.fromJson({
    ..._json(14, 'Ведущий заблокированного', owner: 'Арман Шоу'),
    'publicly_visible': false,
    'visibility_reasons': ['owner_blocked'],
    'owner_blocked_until': '2026-11-25T09:00:00Z',
  }),
];

/// Answers GET /api/listings/:id from [_all] and records writes.
class _Backend implements HttpClientAdapter {
  final writes = <(String, String, Map<String, dynamic>)>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = options.data is Map
        ? Map<String, dynamic>.from(options.data as Map)
        : <String, dynamic>{};
    Map<String, dynamic> data;
    if (options.method == 'GET') {
      final id = int.tryParse(options.path.split('/').last) ?? 0;
      final src = [
        _json(10, 'Ерлан Ведущий', owner: 'Ерлан Events'),
        _json(11, 'Снятый ведущий', active: false, city: 'Астана'),
        // Like the server: the detail never carries the hiding reason.
        _json(12, 'Скрытый ведущий', hiddenAt: '2026-11-18T10:00:00Z'),
        _json(13, 'Grand Hall', category: 1),
        _json(14, 'Ведущий заблокированного', owner: 'Арман Шоу'),
      ].firstWhere((j) => j['id'] == id, orElse: () => _json(id, 'X'));
      data = {'listing': src, 'halls': const [], 'menus': const []};
    } else {
      writes.add((options.method, options.path, body));
      data = {
        'listing': {..._json(12, 'Скрытый ведущий'), ...body, 'id': 12},
        'ok': true,
      };
    }
    return ResponseBody.fromBytes(
      Uint8List.fromList(utf8.encode(jsonEncode(data))),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late _Backend backend;
  late ApiClient client;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backend = _Backend();
    client = ApiClient.test(tokenProvider: () async => 'token');
    client.debugDio.httpClientAdapter = backend;
  });

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    bool admin = true,
    bool dark = false,
    double width = 390,
    double height = 844,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(client),
          isAdminProvider.overrideWithValue(admin),
          categoriesProvider.overrideWith((ref) async => [_venues, _hosts]),
          myListingsProvider.overrideWith((ref) async => _all),
        ],
        child: MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          home: home,
        ),
      ),
    );
    await settle(tester);
  }

  group('filters', () {
    test('search by name in either language or city, any case', () {
      expect(filterAdminListings(_all, query: 'скрыт').map((l) => l.id), [12]);
      expect(filterAdminListings(_all, query: 'АСТАНА').map((l) => l.id), [11]);
      expect(filterAdminListings(_all, query: 'hall кз').map((l) => l.id), [
        13,
      ]);
      expect(filterAdminListings(_all, categoryId: 1).map((l) => l.id), [13]);
      expect(filterAdminListings(_all), hasLength(5));
    });

    test('visibility: the server\'s answer, or the fields as a fallback', () {
      expect(adminVisibility(_all[0]).visible, isTrue);
      expect(adminVisibility(_all[1]).reasons, [
        AdminHideReason.ownerUnpublished,
      ]);
      expect(adminVisibility(_all[2]).reasons, [AdminHideReason.adminHidden]);
      // From the admin list: an owner's block, together with other reasons.
      final blocked = Listing.fromJson({
        ..._json(20, 'Б'),
        'is_active': false,
        'publicly_visible': false,
        'visibility_reasons': ['owner_unpublished', 'owner_blocked'],
        'owner_blocked_until': '2026-11-25T09:00:00Z',
      });
      final v = adminVisibility(blocked);
      expect(v.visible, isFalse);
      expect(v.reasons, [
        AdminHideReason.ownerBlocked,
        AdminHideReason.ownerUnpublished,
      ]);
      expect(v.ownerBlockedUntil, isNotNull);
      final permanent = Listing.fromJson({
        ..._json(21, 'П'),
        'publicly_visible': false,
        'visibility_reasons': ['owner_blocked'],
      });
      expect(adminVisibility(permanent).ownerBlockedUntil, isNull);
    });
  });

  testWidgets('only an administrator opens «Услуги»', (tester) async {
    await pump(tester, const AdminServicesScreen(), admin: false);
    expect(find.byKey(const ValueKey('admin-no-access')), findsOneWidget);
    expect(find.text('Ерлан Ведущий'), findsNothing);
  });

  testWidgets('every listing, unpublished and hidden too, with statuses', (
    tester,
  ) async {
    await pump(tester, const AdminServicesScreen(), height: 2400);
    expect(find.text('Найдено: 5'), findsOneWidget);
    expect(find.text('Владелец заблокирован'), findsOneWidget);
    expect(find.text('Видна посетителям'), findsNWidgets(2));
    expect(find.text('Снята с публикации'), findsOneWidget);
    expect(find.text('Скрыта администратором'), findsOneWidget);
    expect(find.textContaining('Владелец: Ерлан Events'), findsOneWidget);
    expect(find.textContaining('Без владельца'), findsNWidgets(3));
  });

  testWidgets('search and the category filter narrow the list', (tester) async {
    await pump(tester, const AdminServicesScreen());
    await tester.enterText(
      find.byKey(const ValueKey('services-search')),
      'астана',
    );
    await settle(tester);
    expect(find.text('Найдено: 1'), findsOneWidget);
    expect(find.text('Снятый ведущий'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('services-search')), '');
    await tester.tap(find.byKey(const ValueKey('services-cat-1')));
    await settle(tester);
    expect(find.text('Найдено: 1'), findsOneWidget);
    expect(find.text('Grand Hall'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('services-search')),
      'нет такого',
    );
    await settle(tester);
    expect(find.text('Ничего не найдено'), findsOneWidget);
  });

  testWidgets(
    '«Добавить услугу» opens the form; the admin picks the category',
    (tester) async {
      await pump(tester, const AdminServicesScreen());
      await tester.tap(find.byKey(const ValueKey('services-add')));
      await settle(tester);
      expect(find.byType(AdminListingCreateScreen), findsOneWidget);
      expect(find.text('Выберите категорию'), findsOneWidget);
      Navigator.of(tester.element(find.byType(AdminListingCreateScreen))).pop();
      await settle(tester);
      // With a category chosen in the list, the form starts with it.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('services-cat-2')),
        120,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('services-categories')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('services-cat-2')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('services-add')));
      await settle(tester);
      expect(find.text('Ведущие'), findsWidgets);
    },
  );

  testWidgets('a service opens in the form, a restaurant in its tabs', (
    tester,
  ) async {
    await pump(tester, const AdminServicesScreen());
    await tester.tap(find.text('Снятый ведущий'));
    await settle(tester);
    expect(find.byType(AdminServiceEditScreen), findsOneWidget);
    expect(
      find.textContaining('снята с публикации владельцем'),
      findsOneWidget,
    );
    Navigator.of(tester.element(find.byType(AdminServiceEditScreen))).pop();
    await settle(tester);
    // Fourth row sits under the button at this size: find it by search.
    await tester.enterText(
      find.byKey(const ValueKey('services-search')),
      'grand',
    );
    await settle(tester);
    await tester.tap(find.text('Grand Hall'));
    await settle(tester);
    expect(find.byType(RestaurantManageScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('restaurant-toggle-hidden')), findsOne);
  });

  testWidgets('saving a hidden service keeps it hidden and unpublished as is', (
    tester,
  ) async {
    await pump(tester, const AdminServiceEditScreen(listingId: 12));
    expect(
      find.textContaining('скрыта администратором: Жалобы'),
      findsOneWidget,
    );
    expect(find.text('Восстановить'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('alf-submit')));
    await settle(tester);
    final put = backend.writes.single;
    expect(put.$1, 'PUT');
    expect(put.$2, '/api/listings/12');
    // The form never sends the administrator's hiding: the server keeps it.
    expect(put.$3.containsKey('moderation_hidden_at'), isFalse);
    expect(put.$3['is_active'], true);
    expect(backend.writes.where((w) => w.$2.contains('/restore')), isEmpty);
  });

  testWidgets('a blocked owner\'s card says why visitors don\'t see it', (
    tester,
  ) async {
    await pump(tester, const AdminServiceEditScreen(listingId: 14));
    expect(find.textContaining('Не видна посетителям'), findsOneWidget);
    expect(
      find.textContaining('владелец заблокирован до 25.11.2026'),
      findsOneWidget,
    );
    expect(find.textContaining('Видна посетителям.'), findsNothing);
  });

  testWidgets('«Скрыть» asks for a reason and calls the admin action', (
    tester,
  ) async {
    await pump(tester, const AdminServiceEditScreen(listingId: 10));
    await tester.tap(find.byKey(const ValueKey('service-toggle-hidden')));
    await settle(tester);
    expect(find.text('Скрыть карточку?'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('admin-reason')),
      'Нарушение правил',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('admin-confirm')));
    await settle(tester);
    final post = backend.writes.single;
    expect(post.$2, '/api/admin/listings/10/hide');
    expect(post.$3['reason'], 'Нарушение правил');
  });

  testWidgets('«Удалить» confirms first; «Отмена» deletes nothing', (
    tester,
  ) async {
    await pump(tester, const AdminServicesScreen());
    await tester.tap(find.byKey(const ValueKey('service-delete-11')));
    await settle(tester);
    expect(find.text('Удалить «Снятый ведущий»?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('admin-confirm-no')));
    await settle(tester);
    expect(backend.writes, isEmpty);
    await tester.tap(find.byKey(const ValueKey('service-delete-11')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('admin-confirm-yes')));
    await settle(tester);
    expect(backend.writes.single.$1, 'DELETE');
    expect(backend.writes.single.$2, '/api/listings/11');
  });

  for (final dark in [false, true]) {
    testWidgets('fits 320 wide (${dark ? 'dark' : 'light'})', (tester) async {
      await pump(
        tester,
        const AdminServicesScreen(),
        width: 320,
        height: 640,
        dark: dark,
      );
      expect(tester.takeException(), isNull);
      await pump(
        tester,
        const AdminServiceEditScreen(listingId: 12),
        width: 320,
        height: 640,
        dark: dark,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
