import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/network/api_client.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/domain/restaurant/menu_text_import.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/models/listing_hall.dart';
import 'package:mereytoi_app/models/listing_menu.dart';
import 'package:mereytoi_app/models/listing_menu_extra.dart';
import 'package:mereytoi_app/screens/profile/restaurant_admin/tabs/address_tab.dart';
import 'package:mereytoi_app/screens/profile/restaurant_admin/widgets/extra_form_sheet.dart';
import 'package:mereytoi_app/screens/profile/restaurant_admin/widgets/hall_form_sheet.dart';
import 'package:mereytoi_app/screens/profile/restaurant_admin/widgets/menu_form_sheet.dart';
import 'package:mereytoi_app/screens/profile/restaurant_admin/widgets/menu_import_sheet.dart';
import 'package:mereytoi_app/services/upload_service.dart';
import 'package:mereytoi_app/state/listing_management_actions.dart';
import 'package:mereytoi_app/state/provider_onboarding.dart';
import 'package:mereytoi_app/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Answers every write with its own body and an id, and records them.
class _Backend implements HttpClientAdapter {
  final writes = <(String, String, Map<String, dynamic>)>[];
  var _id = 100;

  Iterable<Map<String, dynamic>> bodies(String method, Pattern path) => writes
      .where((w) => w.$1 == method && path.allMatches(w.$2).isNotEmpty)
      .map((w) => w.$3);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = options.data is Map
        ? Map<String, dynamic>.from(options.data as Map)
        : <String, dynamic>{};
    if (options.method != 'GET') {
      writes.add((options.method, options.path, body));
    }
    final row = {'id': _id++, ...body};
    final data = <String, dynamic>{
      'hall': row,
      'menu': row,
      'section': row,
      'item': row,
      'extra': row,
      'listing': row,
      'halls': const [],
      'menus': const [],
    };
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

class _Uploads extends UploadService {
  _Uploads(super.client);

  @override
  Future<List<String>> uploadImages(List<String> filePaths) async => [
    for (var i = 0; i < filePaths.length; i++) '/uploads/new$i.jpg',
  ];
}

ListingHall _hall(int id, {int order = 0, List<String> images = const []}) =>
    ListingHall.fromJson({
      'id': id,
      'listing_id': 7,
      'name_ru': 'Зал $id',
      'name_kz': 'Зал $id кз',
      'description_ru': 'Описание',
      'description_kz': 'Сипаттама',
      'capacity': 50,
      'price': 1000,
      'image_urls': images,
      'is_active': true,
      'sort_order': order,
    });

ListingMenu _menu() => ListingMenu.fromJson({
  'id': 3,
  'listing_id': 7,
  'hall_id': 1,
  'name_ru': 'Банкет',
  'name_kz': 'Банкет кз',
  'description_ru': 'Опис',
  'description_kz': 'Сип',
  'price_per_guest': 12000,
  'min_guests': 20,
  'max_guests': 100,
  'is_active': true,
  'sort_order': 0,
  'sections': [
    {
      'id': 11,
      'menu_id': 3,
      'title_ru': 'Салаты',
      'title_kz': 'Салаттар',
      'sort_order': 0,
      'items': [
        {
          'id': 21,
          'section_id': 11,
          'name_ru': 'Цезарь',
          'name_kz': 'Цезарь кз',
          'quantity_text': '250 г',
          'sort_order': 0,
        },
      ],
    },
  ],
  'extras': [
    {
      'id': 31,
      'menu_id': 3,
      'type': 'decor',
      'title_ru': 'Декор',
      'title_kz': 'Декор кз',
      'price': 5000,
      'unit': 'per_guest',
      'description_ru': 'Цветы',
      'description_kz': 'Гүлдер',
      'sort_order': 0,
    },
  ],
});

void main() {
  late _Backend backend;
  late ProviderContainer container;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backend = _Backend();
    final client = ApiClient.test(tokenProvider: () async => null);
    client.debugDio.httpClientAdapter = backend;
    container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        uploadServiceProvider.overrideWithValue(_Uploads(client)),
        onboardingPhotoPickerProvider.overrideWithValue(
          () async => ['/tmp/a.jpg'],
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  ListingManagementActions actions() =>
      container.read(listingManagementActionsProvider);

  Future<void> pumpSheet(
    WidgetTester tester,
    Widget sheet, {
    bool dark = false,
  }) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          home: Scaffold(body: sheet),
        ),
      ),
    );
    await tester.pump();
  }

  Finder save() => find.widgetWithText(ElevatedButton, 'Сохранить');

  /// Lets a request and the rebuild after it finish.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('parseMenuText, as the admin parses it', () {
    test('sections, items, portions, blank lines', () {
      final parsed = parseMenuText(
        'Салаты\n- Цезарь — 250 г\n• Оливье\n\nГорячее\n- Бешбармак — 1 — порция',
      );
      expect(parsed.map((s) => s.title), ['Салаты', 'Горячее']);
      expect(parsed[0].items.map((i) => i.name), ['Цезарь', 'Оливье']);
      expect(parsed[0].items.first.quantityText, '250 г');
      expect(parsed[1].items.single.quantityText, '1 — порция');
    });

    test('an item before any section lands in «Без названия»', () {
      final parsed = parseMenuText('- Хлеб');
      expect(parsed.single.title, 'Без названия');
      expect(parsed.single.items.single.name, 'Хлеб');
      expect(parseMenuText('  \n '), isEmpty);
    });
  });

  group('list commands', () {
    test('reordering halls that all have order 0 really moves them', () async {
      final a = _hall(1, images: ['/a.jpg']), b = _hall(2), c = _hall(3);
      await actions().reorderHalls(7, [b, a, c]);
      final puts = backend.writes.where((w) => w.$1 == 'PUT').toList();
      // The row already at its position isn't rewritten.
      expect(puts.map((w) => w.$2), [
        '/api/listings/7/halls/1',
        '/api/listings/7/halls/3',
      ]);
      expect(puts.map((w) => w.$3['sort_order']), [1, 2]);
      expect(puts.first.$3['image_urls'], ['/a.jpg']);
      expect(puts.first.$3['description_ru'], 'Описание');
    });

    test('hiding a hall resends everything else unchanged', () async {
      await actions().setHallActive(7, _hall(1, images: ['/a.jpg']), false);
      final body = backend.bodies('PUT', '/halls/1').single;
      expect(body['is_active'], false);
      expect(body['image_urls'], ['/a.jpg']);
      expect(body['capacity'], 50);
      expect(body['name_kz'], 'Зал 1 кз');
    });

    test('a duplicated hall is hidden, last, with its photos', () async {
      await actions().duplicateHall(7, _hall(1, images: ['/a.jpg']), count: 4);
      final body = backend.bodies('POST', '/halls').single;
      expect(body['name_ru'], 'Зал 1 (копия)');
      expect(body['name_kz'], 'Зал 1 кз (көшірме)');
      expect(body['is_active'], false);
      expect(body['sort_order'], 4);
      expect(body['image_urls'], ['/a.jpg']);
    });

    test(
      'a duplicated menu copies sections, items and extras, hidden',
      () async {
        await actions().duplicateMenu(7, _menu(), count: 2);
        final menu = backend.bodies('POST', RegExp(r'/menus$')).single;
        expect(menu['name_ru'], 'Банкет — копия');
        expect(menu['is_active'], false);
        expect(menu['sort_order'], 2);
        expect(menu['price_per_guest'], 12000);
        expect(menu['hall_id'], 1);
        expect(
          backend.bodies('POST', RegExp(r'/sections$')).single['title_ru'],
          'Салаты',
        );
        expect(
          backend.bodies('POST', RegExp(r'/items$')).single['quantity_text'],
          '250 г',
        );
        final extra = backend.bodies('POST', RegExp(r'/extras$')).single;
        expect(extra['description_ru'], 'Цветы');
        expect(extra['unit'], 'per_guest');
      },
    );

    test('a second tap while one command runs is ignored', () async {
      final a = _hall(1), b = _hall(2);
      await Future.wait([
        actions().duplicateHall(7, a, count: 2),
        actions().duplicateHall(7, b, count: 2),
      ]);
      expect(backend.bodies('POST', '/halls'), hasLength(1));
    });
  });

  group('hall form', () {
    testWidgets('a new hall: photo uploaded, saved, at the end of the list', (
      tester,
    ) async {
      await pumpSheet(
        tester,
        const HallFormSheet(listingId: 7, nextSortOrder: 3),
      );
      await tester.enterText(find.byType(TextFormField).at(0), 'Малый');
      await tester.enterText(find.byType(TextFormField).at(1), 'Кіші');
      await tester.tap(find.byKey(const ValueKey('hall-add-photo')));
      await settle(tester);
      expect(backend.writes, isEmpty);
      expect(find.text('Выбрано фото: 1'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('picked-photos-confirm')));
      await settle(tester);
      expect(find.byKey(const ValueKey('hall-photo-0')), findsOneWidget);
      expect(find.text('Обложка'), findsOneWidget);
      await tester.tap(save());
      await settle(tester);
      final body = backend.bodies('POST', '/halls').single;
      expect(body['image_urls'], ['/uploads/new0.jpg']);
      expect(body['sort_order'], 3);
    });

    testWidgets('a cancelled check adds no photo', (tester) async {
      await pumpSheet(tester, const HallFormSheet(listingId: 7));
      await tester.tap(find.byKey(const ValueKey('hall-add-photo')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('picked-photos-cancel')));
      await settle(tester);
      expect(find.byKey(const ValueKey('hall-photo-0')), findsNothing);
    });

    testWidgets('both names are required, nothing is sent without them', (
      tester,
    ) async {
      await pumpSheet(tester, const HallFormSheet(listingId: 7));
      await tester.enterText(find.byType(TextFormField).at(0), 'Малый');
      await tester.tap(save());
      await settle(tester);
      expect(backend.writes, isEmpty);
    });

    testWidgets('editing keeps photos, a removed one goes', (tester) async {
      await pumpSheet(
        tester,
        HallFormSheet(
          listingId: 7,
          existing: _hall(1, images: ['/a.jpg', '/b.jpg']),
        ),
      );
      expect(find.byKey(const ValueKey('hall-photo-1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('hall-photo-remove-0')));
      await settle(tester);
      await tester.tap(save());
      await settle(tester);
      expect(backend.bodies('PUT', '/halls/1').single['image_urls'], [
        '/b.jpg',
      ]);
    });

    testWidgets('no overflow in the dark theme', (tester) async {
      await pumpSheet(
        tester,
        HallFormSheet(listingId: 7, existing: _hall(1, images: ['/a.jpg'])),
        dark: true,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('extra form', () {
    ListingMenuExtra extra({
      String type = 'decor',
      String unit = 'per_guest',
    }) => ListingMenuExtra.fromJson({
      'id': 31,
      'menu_id': 3,
      'type': type,
      'title_ru': 'Декор',
      'title_kz': 'Декор кз',
      'price': 5000,
      'unit': unit,
      'description_ru': 'Цветы',
      'description_kz': 'Гүлдер',
      'sort_order': 2,
    });

    testWidgets('saving keeps the description (it used to be wiped)', (
      tester,
    ) async {
      await pumpSheet(
        tester,
        ExtraFormSheet(listingId: 7, menuId: 3, existing: extra()),
      );
      await tester.tap(save());
      await settle(tester);
      final body = backend.bodies('PUT', '/extras/31').single;
      expect(body['description_ru'], 'Цветы');
      expect(body['description_kz'], 'Гүлдер');
    });

    testWidgets('a type or unit set elsewhere doesn\'t crash the form', (
      tester,
    ) async {
      await pumpSheet(
        tester,
        ExtraFormSheet(
          listingId: 7,
          menuId: 3,
          existing: extra(type: 'custom_type', unit: 'per_hour'),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(save());
      await settle(tester);
      final body = backend.bodies('PUT', '/extras/31').single;
      expect(body['type'], 'custom_type');
      expect(body['unit'], 'per_hour');
    });
  });

  group('menu form', () {
    testWidgets('a price is optional, as in the admin', (tester) async {
      await pumpSheet(
        tester,
        const MenuFormSheet(listingId: 7, halls: [], nextSortOrder: 5),
      );
      await tester.enterText(find.byType(TextFormField).at(0), 'Банкет');
      await tester.enterText(find.byType(TextFormField).at(1), 'Банкет кз');
      await tester.tap(save());
      await settle(tester);
      final body = backend.bodies('POST', '/menus').single;
      expect(body['price_per_guest'], 0);
      expect(body['sort_order'], 5);
    });

    testWidgets('an end date before the start date is refused', (tester) async {
      final json = {
        'id': 3,
        'name_ru': 'Банкет',
        'name_kz': 'Банкет кз',
        'is_active': true,
        'valid_from': '2026-12-10T00:00:00Z',
        'valid_until': '2026-12-01T00:00:00Z',
      };
      await pumpSheet(
        tester,
        MenuFormSheet(
          listingId: 7,
          halls: const [],
          existing: ListingMenu.fromJson(json),
        ),
      );
      await tester.tap(save());
      await settle(tester);
      expect(backend.writes, isEmpty);
      expect(find.textContaining('не может быть раньше'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('menu-clear-dates')));
      await settle(tester);
      await tester.tap(save());
      await settle(tester);
      final body = backend.bodies('PUT', '/menus/3').single;
      expect(body['valid_from'], isNull);
      expect(body['valid_until'], isNull);
    });
  });

  group('menu from text', () {
    testWidgets('nothing is written before the explicit confirm', (
      tester,
    ) async {
      await pumpSheet(
        tester,
        const MenuImportSheet(listingId: 7, menuId: 3, existingSectionCount: 2),
      );
      final next = find.widgetWithText(ElevatedButton, 'Показать результат');
      await tester.tap(next);
      await settle(tester);
      expect(find.text('Введите текст меню'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('menu-import-text')),
        'Салаты\n- Цезарь — 250 г\n- Оливье',
      );
      await tester.tap(next);
      await settle(tester);
      expect(
        find.text('Будет добавлено разделов: 1, позиций: 2'),
        findsOneWidget,
      );
      expect(backend.writes, isEmpty);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Добавить в меню'));
      await settle(tester);
      final section = backend.bodies('POST', RegExp(r'/sections$')).single;
      expect(section['sort_order'], 2);
      expect(section['title_kz'], 'Салаты');
      final items = backend.bodies('POST', RegExp(r'/items$')).toList();
      expect(items.map((i) => i['name_ru']), ['Цезарь', 'Оливье']);
      expect(items.first['quantity_text'], '250 г');
      expect(items.last['sort_order'], 1);
    });
  });

  group('address tab', () {
    final listing = Listing.fromJson({
      'id': 7,
      'category_id': 1,
      'name_ru': 'Ресторан',
      'name_kz': 'Ресторан',
      'latitude': 43.25,
      'longitude': 76.95,
      'address': 'Абая 1',
    });

    Future<void> pumpTab(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(body: AddressTab(listing: listing)),
          ),
        ),
      );
      await settle(tester);
    }

    Finder saveTab() => find.text('Сохранить');

    testWidgets('both coordinates empty clears the point', (tester) async {
      await pumpTab(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Latitude'),
        '',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Longitude'),
        '',
      );
      await tester.tap(saveTab());
      await settle(tester);
      final body = backend.bodies('PUT', '/api/listings/7').single;
      expect(body['latitude'], isNull);
      expect(body['longitude'], isNull);
    });

    testWidgets('one coordinate or an impossible one is refused', (
      tester,
    ) async {
      await pumpTab(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Longitude'),
        '',
      );
      await tester.tap(saveTab());
      await settle(tester);
      expect(find.textContaining('Укажите обе координаты'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Longitude'),
        '500',
      );
      await tester.tap(saveTab());
      await settle(tester);
      expect(backend.writes, isEmpty);
    });
  });
}
