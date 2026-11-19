import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/network/api_client.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/domain/admin/admin_listing_form.dart';
import 'package:mereytoi_app/models/category.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/screens/admin/admin_listing_form_screen.dart';
import 'package:mereytoi_app/screens/profile/restaurant_admin/restaurant_admin_list_screen.dart';
import 'package:mereytoi_app/screens/profile/restaurant_admin/restaurant_manage_screen.dart';
import 'package:mereytoi_app/screens/profile/restaurant_admin/tabs/address_tab.dart';
import 'package:mereytoi_app/screens/profile/restaurant_admin/widgets/extra_form_sheet.dart';
import 'package:mereytoi_app/screens/profile/restaurant_admin/widgets/hall_form_sheet.dart';
import 'package:mereytoi_app/screens/profile/restaurant_admin/widgets/menu_form_sheet.dart';
import 'package:mereytoi_app/services/upload_service.dart';
import 'package:mereytoi_app/state/admin_providers.dart';
import 'package:mereytoi_app/state/categories_provider.dart';
import 'package:mereytoi_app/state/listings_provider.dart';
import 'package:mereytoi_app/state/provider_onboarding.dart';
import 'package:mereytoi_app/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _venues = Category(
  id: 3,
  slug: 'venues',
  nameRu: 'Рестораны и локации',
  nameKz: 'Мейрамханалар',
  position: 1,
);
const _decor = Category(
  id: 4,
  slug: 'decor',
  nameRu: 'Декор',
  nameKz: 'Декор',
  position: 2,
);

/// Answers writes with their own body plus an id, and records them.
class _Backend implements HttpClientAdapter {
  final writes = <(String, String, Map<String, dynamic>)>[];
  Completer<void>? gate;

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
      if (gate != null) await gate!.future;
    }
    final listing = {
      'id': 77,
      'category_id': 3,
      'name_ru': 'Новый',
      'name_kz': 'Жаңа',
      ...body,
    };
    final data = <String, dynamic>{
      'listing': listing,
      'hall': {'id': 5, ...body},
      'menu': {'id': 6, ...body},
      'extra': {'id': 8, ...body},
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

  Completer<void>? photoGate;
  final videoCalls = <String>[];

  @override
  Future<List<String>> uploadImages(List<String> filePaths) async {
    if (photoGate != null) await photoGate!.future;
    return [for (var i = 0; i < filePaths.length; i++) '/uploads/p$i.jpg'];
  }

  @override
  Future<String> uploadVideo(String filePath) async {
    videoCalls.add(filePath);
    return '/uploads/v${videoCalls.length}.mp4';
  }
}

Listing _listing({Map<String, dynamic> extra = const {}}) => Listing.fromJson({
  'id': 7,
  'category_id': 3,
  'category': {
    'id': 3,
    'slug': 'venues',
    'name_ru': 'Рестораны',
    'name_kz': 'Р',
  },
  'name_ru': 'Астана Холл',
  'name_kz': 'Астана Холл',
  'description_ru': 'Описание',
  'description_kz': 'Сипаттама',
  'city': 'Алматы',
  'phone': '+77001112233',
  'price': 15000,
  'min_guests': 50,
  'max_guests': 400,
  'rating': 4.5,
  'emoji': '🍽️',
  'color_from': '#112233',
  'color_to': '#445566',
  'image_urls': ['/uploads/a.jpg'],
  'video_urls': ['/uploads/v.mp4'],
  'address': 'Абая 1',
  'latitude': 43.25,
  'longitude': 76.95,
  'place_id': 'ChIJ123',
  'capacity': 300,
  'price_type': 'fixed',
  'is_active': false,
  ...extra,
});

void main() {
  late _Backend backend;
  late _Uploads uploads;
  late ApiClient client;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backend = _Backend();
    client = ApiClient.test(tokenProvider: () async => 'token');
    client.debugDio.httpClientAdapter = backend;
    uploads = _Uploads(client);
  });

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    bool admin = true,
    bool dark = false,
    double width = 390,
    double height = 844,
    List<Listing> mine = const [],
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(client),
          uploadServiceProvider.overrideWithValue(uploads),
          isAdminProvider.overrideWithValue(admin),
          categoriesProvider.overrideWith((ref) async => [_venues, _decor]),
          myListingsProvider.overrideWith((ref) async => mine),
          onboardingPhotoPickerProvider.overrideWithValue(
            () async => ['/tmp/a.jpg'],
          ),
          adminVideoPickerProvider.overrideWithValue(
            () async => ['/tmp/1.mov', '/tmp/2.mp4'],
          ),
        ],
        child: MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          home: home,
        ),
      ),
    );
    await settle(tester);
  }

  /// Scrolls the lazily built form until [key] is built and clear of the
  /// sticky button bar.
  Future<Finder> reveal(WidgetTester tester, String key) async {
    final f = find.byKey(ValueKey(key));
    final form = find.byKey(const ValueKey('admin-listing-form'));
    if (form.evaluate().isNotEmpty) {
      final scrollable = find
          .descendant(of: form, matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(f, 120, scrollable: scrollable);
      final box = tester.getRect(f);
      final bar = tester.getRect(find.byKey(const ValueKey('alf-submit')));
      if (box.bottom > bar.top - 16 && key != 'alf-submit') {
        await tester.drag(scrollable, Offset(0, -(box.bottom - bar.top + 80)));
        await tester.pump();
      }
    } else {
      await tester.ensureVisible(f);
    }
    // Let any scroll momentum end: a tap on a moving list only stops it.
    await settle(tester);
    return f;
  }

  Future<void> fill(WidgetTester tester, String key, String text) async {
    await tester.enterText(await reveal(tester, key), text);
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(await reveal(tester, key));
    await settle(tester);
  }

  group('ServiceForm rules', () {
    test('defaults are the web form\'s EMPTY', () {
      final v = AdminListingValues(categoryId: 3);
      final body = adminListingPayload(v);
      expect(body['emoji'], '✨');
      expect(body['color_from'], '#3a1420');
      expect(body['color_to'], '#d4af6a');
      expect(body['price'], 0);
      expect(body['rating'], 0);
      expect(body['image_urls'], isEmpty);
      // A new listing sends no address/publication: the server publishes
      // it and assigns no owner.
      expect(body.containsKey('is_active'), isFalse);
      expect(body.containsKey('address'), isFalse);
    });

    test('the browser\'s input checks', () {
      final v = AdminListingValues()
        ..rating = '5.5'
        ..price = '-1'
        ..emoji = '12345'
        ..colorTo = 'red';
      final e = validateAdminListing(v);
      expect(e.nameRu, isNotNull);
      expect(e.nameKz, isNotNull);
      expect(e.category, isNotNull);
      expect(e.rating, isNotNull);
      expect(e.price, isNotNull);
      expect(e.emoji, isNotNull);
      expect(e.colorTo, isNotNull);
      expect(e.colorFrom, isNull);

      final ok = AdminListingValues(categoryId: 3)
        ..nameRu = 'А'
        ..nameKz = 'Б'
        ..rating = '4,7'
        ..price = ''
        ..emoji = '🍽️';
      expect(validateAdminListing(ok).isEmpty, isTrue);
      expect(adminListingPayload(ok)['rating'], 4.7);
      expect(adminListingPayload(ok)['price'], 0);
      expect(validateAdminListing(ok..rating = '4.75').rating, isNotNull);
      // An owner-made listing has no colours; that never blocks a save.
      final noColours = AdminListingValues(categoryId: 3)
        ..nameRu = 'А'
        ..nameKz = 'Б'
        ..colorFrom = ''
        ..colorTo = '';
      expect(validateAdminListing(noColours).isEmpty, isTrue);
      expect(adminListingPayload(noColours)['color_from'], '');
    });

    test('editing resends what the form doesn\'t show', () {
      final l = _listing();
      final v = AdminListingValues.fromListing(l)..nameRu = 'Новое';
      final body = adminListingPayload(v, existing: l);
      expect(body['name_ru'], 'Новое');
      expect(body['rating'], 4.5);
      expect(body['address'], 'Абая 1');
      expect(body['latitude'], 43.25);
      expect(body['place_id'], 'ChIJ123');
      expect(body['capacity'], 300);
      expect(body['is_active'], false);
      expect(body['video_urls'], ['/uploads/v.mp4']);
    });

    test('poster path follows the server\'s naming', () {
      expect(videoPosterPath('/uploads/123.mp4'), '/uploads/posters/123.jpg');
      expect(videoPosterPath('https://x/y.mp4'), isNull);
    });
  });

  group('create a restaurant', () {
    testWidgets('only an administrator can open the form', (tester) async {
      await pump(tester, const AdminListingCreateScreen(), admin: false);
      expect(find.byKey(const ValueKey('admin-no-access')), findsOneWidget);
      expect(find.byKey(const ValueKey('admin-listing-form')), findsNothing);
    });

    testWidgets('the list offers «Добавить ресторан» only to an admin', (
      tester,
    ) async {
      await pump(tester, const RestaurantAdminListScreen(), admin: false);
      expect(find.byKey(const ValueKey('restaurants-add')), findsNothing);
      await pump(tester, const RestaurantAdminListScreen());
      expect(find.byKey(const ValueKey('restaurants-add')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('restaurants-add')));
      await settle(tester);
      expect(find.text('Новая услуга'), findsOneWidget);
      // The category starts as «Рестораны и локации».
      expect(find.text('Рестораны и локации'), findsWidgets);
    });

    testWidgets('empty required fields send nothing', (tester) async {
      await pump(tester, const AdminListingCreateScreen());
      await tapKey(tester, 'alf-submit');
      expect(backend.writes, isEmpty);
      expect(find.text('Заполните это поле'), findsNWidgets(2));
      expect(find.text('Выберите категорию'), findsWidgets);
    });

    testWidgets(
      'every field, photos and videos go in one POST, then halls/menus open',
      (tester) async {
        await pump(tester, const AdminListingCreateScreen(presetCategoryId: 3));
        await fill(tester, 'alf-name-ru', 'Тест Холл');
        await fill(tester, 'alf-name-kz', 'Тест Холл кз');
        await fill(tester, 'alf-desc-ru', 'Описание');
        await fill(tester, 'alf-desc-kz', 'Сипаттама');
        await fill(tester, 'alf-city', 'Алматы');
        await fill(tester, 'alf-phone', '+77001234567');
        await fill(tester, 'alf-price', '12000');
        await fill(tester, 'alf-rating', '4.8');
        await fill(tester, 'alf-min-guests', '50');
        await fill(tester, 'alf-max-guests', '300');
        await fill(tester, 'alf-emoji', '🍽️');

        await tapKey(tester, 'alf-color-from');
        await tester.tap(find.byKey(const ValueKey('color-#1f3a5f')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('color-done')));
        await settle(tester);

        await tapKey(tester, 'alf-add-photos');
        await tester.tap(find.byKey(const ValueKey('picked-photos-confirm')));
        await settle(tester);
        expect(find.text('Обложка'), findsOneWidget);

        await tapKey(tester, 'alf-add-videos');
        // One at a time, in the picked order.
        expect(uploads.videoCalls, ['/tmp/1.mov', '/tmp/2.mp4']);
        expect(backend.writes, isEmpty);

        await tapKey(tester, 'alf-submit');
        final body = backend.bodies('POST', '/api/listings').single;
        expect(body, {
          'category_id': 3,
          'name_ru': 'Тест Холл',
          'name_kz': 'Тест Холл кз',
          'description_ru': 'Описание',
          'description_kz': 'Сипаттама',
          'city': 'Алматы',
          'phone': '+77001234567',
          'price': 12000,
          'min_guests': 50,
          'max_guests': 300,
          'rating': 4.8,
          'emoji': '🍽️',
          'color_from': '#1f3a5f',
          'color_to': '#d4af6a',
          'image_urls': ['/uploads/p0.jpg'],
          'video_urls': ['/uploads/v1.mp4', '/uploads/v2.mp4'],
        });
        expect(find.byType(RestaurantManageScreen), findsOneWidget);
      },
    );

    testWidgets('a double tap creates one listing', (tester) async {
      backend.gate = Completer<void>();
      await pump(tester, const AdminListingCreateScreen(presetCategoryId: 3));
      await fill(tester, 'alf-name-ru', 'А');
      await fill(tester, 'alf-name-kz', 'Б');
      final submit = find.byKey(const ValueKey('alf-submit'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump();
      await tester.tap(submit, warnIfMissed: false);
      await tester.pump();
      expect(find.text('Сохраняем…'), findsOneWidget);
      backend.gate!.complete();
      await settle(tester);
      expect(backend.bodies('POST', '/api/listings'), hasLength(1));
    });

    testWidgets('no save while a photo is still uploading', (tester) async {
      uploads.photoGate = Completer<void>();
      await pump(tester, const AdminListingCreateScreen(presetCategoryId: 3));
      await fill(tester, 'alf-name-ru', 'А');
      await fill(tester, 'alf-name-kz', 'Б');
      await tapKey(tester, 'alf-add-photos');
      await tester.tap(find.byKey(const ValueKey('picked-photos-confirm')));
      await settle(tester);
      expect(find.text('Загружаем фото…'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('alf-submit')));
      await settle(tester);
      expect(backend.writes, isEmpty);
      uploads.photoGate!.complete();
      await settle(tester);
      await tapKey(tester, 'alf-submit');
      expect(backend.bodies('POST', '/api/listings').single['image_urls'], [
        '/uploads/p0.jpg',
      ]);
    });

    testWidgets('another category creates a service and closes', (
      tester,
    ) async {
      await pump(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      const AdminListingCreateScreen(presetCategoryId: 4),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester);
      await fill(tester, 'alf-name-ru', 'Шары');
      await fill(tester, 'alf-name-kz', 'Шарлар');
      await tapKey(tester, 'alf-submit');
      expect(backend.bodies('POST', '/api/listings').single['category_id'], 4);
      expect(find.byType(AdminListingCreateScreen), findsNothing);
      expect(find.byType(RestaurantManageScreen), findsNothing);
    });

    testWidgets('buttons stay on one line with large system text', (
      tester,
    ) async {
      await pump(
        tester,
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: const AdminListingCreateScreen(presetCategoryId: 3),
          ),
        ),
        width: 320,
        height: 640,
      );
      for (final label in ['Отмена', 'Создать услугу']) {
        final h = tester.getSize(find.text(label)).height;
        // One line of the label, not two.
        expect(h, lessThan(40), reason: label);
      }
      expect(tester.takeException(), isNull);
    });

    for (final dark in [false, true]) {
      testWidgets('fits 320 wide (${dark ? 'dark' : 'light'})', (tester) async {
        await pump(
          tester,
          const AdminListingCreateScreen(presetCategoryId: 3),
          width: 320,
          height: 640,
          dark: dark,
        );
        await tapKey(tester, 'alf-submit');
        final list = find.byKey(const ValueKey('admin-listing-form'));
        await tester.drag(list, const Offset(0, -3000));
        await settle(tester);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('alf-preview')), findsOneWidget);
      });
    }
  });

  group('admin edit and the other tabs', () {
    testWidgets('«Сохранить изменения» resends the whole listing', (
      tester,
    ) async {
      final l = _listing();
      await pump(tester, Scaffold(body: AdminListingForm(existing: l)));
      expect(find.text('Сохранить изменения'), findsOneWidget);
      await fill(tester, 'alf-name-ru', 'Астана Холл 2');
      await tapKey(tester, 'alf-submit');
      final body = backend.bodies('PUT', '/api/listings/7').single;
      expect(body['name_ru'], 'Астана Холл 2');
      expect(body['is_active'], false);
      expect(body['place_id'], 'ChIJ123');
      expect(body['video_urls'], ['/uploads/v.mp4']);
      expect(find.text('Сохранено'), findsOneWidget);
      // Editing again brings the save button back.
      await fill(tester, 'alf-city', 'Астана');
      await tester.pump();
      expect(find.text('Сохранить изменения'), findsOneWidget);
    });

    testWidgets('admin address: city, read-only Place ID, no capacity', (
      tester,
    ) async {
      final l = _listing();
      await pump(tester, Scaffold(body: AddressTab(listing: l, admin: true)));
      expect(find.byKey(const ValueKey('address-city')), findsOneWidget);
      expect(find.byKey(const ValueKey('address-pick-map')), findsOneWidget);
      expect(find.text('Общая вместимость'), findsNothing);
      final placeId = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey('address-place-id')),
          matching: find.byType(TextField),
        ),
      );
      expect(placeId.readOnly, isTrue);
      await tester.enterText(
        find.byKey(const ValueKey('address-city')),
        'Астана',
      );
      await tester.tap(find.text('Сохранить адрес'));
      await settle(tester);
      final body = backend.bodies('PUT', '/api/listings/7').single;
      expect(body['city'], 'Астана');
      expect(body['place_id'], 'ChIJ123');
      expect(body['capacity'], 300);
    });

    testWidgets('an owner keeps the owner\'s address form', (tester) async {
      await pump(tester, Scaffold(body: AddressTab(listing: _listing())));
      expect(find.byKey(const ValueKey('address-city')), findsNothing);
      expect(find.text('Общая вместимость'), findsOneWidget);
    });

    testWidgets('a hall\'s display order is saved', (tester) async {
      await pump(
        tester,
        const Scaffold(body: HallFormSheet(listingId: 7, nextSortOrder: 2)),
        height: 2000,
      );
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const ValueKey('sort-order')),
                matching: find.byType(TextField),
              ),
            )
            .controller!
            .text,
        '2',
      );
      await tester.enterText(find.byType(TextFormField).at(0), 'Малый');
      await tester.enterText(find.byType(TextFormField).at(1), 'Кіші');
      await tester.enterText(find.byKey(const ValueKey('sort-order')), '0');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Сохранить'));
      await settle(tester);
      expect(backend.bodies('POST', '/halls').single['sort_order'], 0);
    });

    testWidgets('a menu\'s display order is saved', (tester) async {
      await pump(
        tester,
        const Scaffold(
          body: MenuFormSheet(listingId: 7, halls: [], nextSortOrder: 1),
        ),
        height: 2400,
      );
      await tester.enterText(find.byType(TextFormField).at(0), 'Банкет');
      await tester.enterText(find.byType(TextFormField).at(1), 'Банкет кз');
      await tester.enterText(find.byKey(const ValueKey('sort-order')), '5');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Сохранить'));
      await settle(tester);
      expect(
        backend.bodies('POST', RegExp(r'/menus$')).single['sort_order'],
        5,
      );
    });

    testWidgets('a new option is named after its type, as the presets', (
      tester,
    ) async {
      await pump(
        tester,
        const Scaffold(body: ExtraFormSheet(listingId: 7, menuId: 6)),
        height: 2000,
      );
      expect(find.text('Детский стол'), findsWidgets);
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await settle(tester);
      await tester.tap(find.text('Декор').last);
      await settle(tester);
      final ru = tester.widget<TextFormField>(find.byType(TextFormField).at(0));
      expect(ru.controller!.text, 'Декор');
    });
  });
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
