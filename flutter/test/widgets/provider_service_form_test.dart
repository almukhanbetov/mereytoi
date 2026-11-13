import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/models/category.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/screens/profile/provider/my_services_screen.dart';
import 'package:mereytoi_app/screens/profile/provider/widgets/provider_service_form_sheet.dart';
import 'package:mereytoi_app/services/upload_service.dart';
import 'package:mereytoi_app/state/categories_provider.dart';
import 'package:mereytoi_app/state/city_provider.dart';
import 'package:mereytoi_app/state/listings_provider.dart';
import 'package:mereytoi_app/state/locale_provider.dart';
import 'package:mereytoi_app/state/provider_onboarding.dart';
import 'package:mereytoi_app/state/provider_provider.dart';
import 'package:mereytoi_app/state/providers.dart';
import 'package:mereytoi_app/widgets/city_selector.dart';
import 'package:mereytoi_app/widgets/services/services_category_grid.dart';
import 'package:mereytoi_app/screens/profile/restaurant_admin/restaurant_manage_screen.dart';
import 'package:mereytoi_app/screens/profile/provider/widgets/provider_profile_form_sheet.dart';
import 'package:mereytoi_app/screens/profile/provider/widgets/location_picker_screen.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/city_fake_api.dart';
import '../helpers/provider_fake_api.dart';

const _categories = [
  Category(
    id: 1,
    slug: 'venues',
    nameRu: 'Рестораны и локации',
    nameKz: 'Мейрамханалар',
    position: 1,
  ),
  Category(
    id: 2,
    slug: 'hosts',
    nameRu: 'Ведущие',
    nameKz: 'Жүргізушілер',
    position: 2,
  ),
  Category(
    id: 4,
    slug: 'artists',
    nameRu: 'Артисты и исполнители',
    nameKz: 'Әртістер мен орындаушылар',
    position: 4,
  ),
];

/// Upload stand-in: by default returns one URL per file; tests can make it
/// wait or fail.
class _Uploads extends UploadService {
  _Uploads(super.client);

  Completer<void>? gate;
  int failNext = 0;
  final calls = <List<String>>[];
  var _n = 0;

  @override
  Future<List<String>> uploadImages(List<String> filePaths) async {
    calls.add(filePaths);
    if (gate != null) await gate!.future;
    if (failNext > 0) {
      failNext--;
      throw Exception('upload failed');
    }
    return [for (final _ in filePaths) '/uploads/f${_n++}.jpg'];
  }
}

Map<String, dynamic> _listing(
  int id, {
  int categoryId = 2,
  String name = 'Проведение тоя',
  String nameKz = 'Той жүргізу',
  String city = 'Алматы',
  int price = 150000,
  String priceType = 'from',
  List<String> images = const ['/uploads/a.jpg', '/uploads/b.jpg'],
}) => {
  'id': id,
  'category_id': categoryId,
  'name_ru': name,
  'name_kz': nameKz,
  'description_ru': 'Описание',
  'description_kz': 'Описание',
  'city': city,
  'price': price,
  'price_type': priceType,
  'image_urls': images,
  'is_active': true,
  'rating': 4.5,
};

/// Network photo placeholders animate forever in tests, so pumpAndSettle
/// would never return — pump a fixed stretch of frames instead.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  Future<(ProviderFakeApi, _Uploads, ProviderContainer)> pump(
    WidgetTester tester, {
    bool withListing = true,
    String providerCity = 'Астана',
    String providerPhone = '',
    String providerWhatsapp = '',
    Size size = const Size(390, 844),
    ThemeData Function()? theme,
    AppLocale locale = AppLocale.ru,
    List<String>? pickedPhotos,
  }) async {
    SharedPreferences.setMockInitialValues({
      if (locale != AppLocale.ru) 'app_locale_v1': locale.name,
    });
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final (client, api) = fakeProviderApi(
      existingProvider: {
        'id': 5,
        'user_id': 1,
        'display_name': 'Dana',
        'city': providerCity,
        'phone': providerPhone,
        'whatsapp': providerWhatsapp,
        'status': 'active',
      },
    );
    if (withListing) api.listings.add(_listing(101));
    final uploads = _Uploads(client);
    final photos = pickedPhotos ?? tempPhotos(3);
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        categoriesProvider.overrideWith((ref) => Future.value(_categories)),
        citiesProvider.overrideWith((ref) => Future.value(testCities)),
        uploadServiceProvider.overrideWithValue(uploads),
        onboardingPhotoPickerProvider.overrideWithValue(() async => photos),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: (theme ?? () => AppTheme.light)(),
          home: const MyServicesScreen(),
        ),
      ),
    );
    await settle(tester);
    return (api, uploads, container);
  }

  /// «Добавить услугу» → the category list → the form. Tile 0 is
  /// «Рестораны и локации», tile 1 «Ведущие».
  Future<void> openCreate(WidgetTester tester, {int tile = 1}) async {
    await tester.tap(find.byKey(const ValueKey('my-services-add')));
    await settle(tester);
    expect(find.byType(ProviderServiceFormScreen), findsNothing);
    await tester.tap(find.byType(ServicesCategoryTile).at(tile));
    await settle(tester);
    expect(find.byType(ProviderServiceFormScreen), findsOneWidget);
  }

  Finder categoryCard() => find.byKey(const ValueKey('service-category'));

  /// Edit [listing] directly, the way «Мои услуги» and «Основное» open it.
  Future<void> openEdit(
    WidgetTester tester,
    Map<String, dynamic> listing,
  ) async {
    openProviderServiceForm(
      tester.element(find.byType(MyServicesScreen)),
      existing: Listing.fromJson(listing),
    );
    await settle(tester);
    expect(find.byType(ProviderServiceFormScreen), findsOneWidget);
  }

  Map<String, dynamic> restaurant(int id) => {
    ..._listing(id, categoryId: 1, name: 'Алтын', nameKz: 'Алтын'),
    'phone': '+7 777 123 45 67',
    'address': 'ул. Абая, 1',
    'latitude': 43.25,
    'longitude': 76.95,
    'price': 5000,
    'min_guests': 20,
    'max_guests': 300,
    'capacity': 300,
  };

  /// Scrolls the form (either direction) until [f] is built and visible.
  Future<void> scrollTo(WidgetTester tester, Finder f) async {
    final scrollable = find
        .descendant(
          of: find.byType(ProviderServiceFormScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    for (final delta in [200.0, -200.0]) {
      if (f.evaluate().isNotEmpty) break;
      try {
        await tester.scrollUntilVisible(
          f,
          delta,
          scrollable: scrollable,
          maxScrolls: 30,
        );
      } catch (_) {}
    }
    await tester.ensureVisible(f);
    await settle(tester);
  }

  Future<void> enter(WidgetTester tester, String key, String text) async {
    final f = find.byKey(ValueKey(key));
    await scrollTo(tester, f);
    await tester.enterText(f, text);
    await tester.pump();
  }

  Finder submit() => find.byKey(const ValueKey('service-submit'));

  /// The gallery, then the check of what it returned, then «Загрузить».
  Future<void> addPhotos(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('service-add-photo')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('picked-photos-confirm')));
    await settle(tester);
  }

  Map<dynamic, dynamic> lastCreateBody(ProviderFakeApi api) =>
      api.bodies['POST /api/provider/me/listings']!.last! as Map;

  testWidgets(
    'create: prefilled city/category, photos, publish → closes, snackbar, list refreshed',
    (tester) async {
      final (api, uploads, _) = await pump(tester);
      await openCreate(tester);
      expect(find.text('Новая услуга'), findsOneWidget);
      expect(find.text('Опубликовать услугу'), findsOneWidget);
      // The category just picked and the profile's city.
      final category = find.byKey(const ValueKey('service-category'));
      await scrollTo(tester, category);
      expect(
        find.descendant(of: category, matching: find.text('Ведущие')),
        findsOneWidget,
      );
      final city = find.byKey(const ValueKey('service-city'));
      await scrollTo(tester, city);
      expect(
        find.descendant(of: city, matching: find.text('Астана')),
        findsOneWidget,
      );

      await enter(tester, 'service-name', 'Шоу мыльных пузырей');
      await enter(tester, 'service-description', 'Для детей и взрослых');
      await enter(tester, 'service-price', '45000');
      final perEvent = find.byKey(const ValueKey('price-type-per_event'));
      await scrollTo(tester, perEvent);
      await tester.tap(perEvent);
      await scrollTo(tester, find.byKey(const ValueKey('service-add-photo')));
      await addPhotos(tester);
      await settle(tester);
      expect(uploads.calls, hasLength(1));
      expect(find.text('Обложка'), findsOneWidget);

      await tester.tap(submit());
      await settle(tester);

      expect(find.byType(ProviderServiceFormScreen), findsNothing);
      expect(find.text('Услуга опубликована'), findsOneWidget);
      expect(
        find.text('Шоу мыльных пузырей'),
        findsOneWidget,
      ); // list refreshed
      final body = lastCreateBody(api);
      expect(body['category_id'], 2);
      expect(body['city'], 'Астана');
      expect(body['name_ru'], 'Шоу мыльных пузырей');
      expect(body['name_kz'], 'Шоу мыльных пузырей'); // KZ falls back
      expect(body['price'], 45000);
      expect(body['price_type'], 'per_event');
      expect(body['image_urls'], [
        '/uploads/f0.jpg',
        '/uploads/f1.jpg',
        '/uploads/f2.jpg',
      ]);
    },
  );

  group('business contact in the service form', () {
    Finder number() => find.byKey(const ValueKey('service-business-phone'));

    testWidgets('shows the number clients will see', (tester) async {
      await pump(tester, providerPhone: '+7 701 111 22 33');
      await openCreate(tester);
      await scrollTo(tester, number());
      expect(tester.widget<Text>(number()).data, '+7 701 111 22 33');
      expect(find.text('Этот номер увидят клиенты'), findsOneWidget);
      expect(find.textContaining('Кнопка связи'), findsNothing);
    });

    testWidgets('says so when none is set', (tester) async {
      await pump(tester);
      await openCreate(tester);
      await scrollTo(tester, number());
      expect(tester.widget<Text>(number()).data, 'Не указан');
    });

    testWidgets('a messenger taking over the contact button is mentioned', (
      tester,
    ) async {
      await pump(
        tester,
        providerPhone: '+7 701 111 22 33',
        providerWhatsapp: '+7 702 000 00 00',
      );
      await openCreate(tester);
      await scrollTo(tester, number());
      expect(
        find.text('Кнопка связи сейчас открывает WhatsApp'),
        findsOneWidget,
      );
    });

    testWidgets('editing it updates the card and keeps what was typed', (
      tester,
    ) async {
      final (api, _, _) = await pump(tester);
      await openCreate(tester);
      await enter(tester, 'service-name', 'Черновик');
      final edit = find.byKey(const ValueKey('service-business-phone-edit'));
      await scrollTo(tester, edit);
      await tester.tap(edit);
      await settle(tester);

      final phone = find.byKey(const ValueKey('provider-profile-phone'));
      await tester.ensureVisible(phone);
      await tester.enterText(phone, '+7 705 555 55 55');
      await tester.pump();
      final save = find.descendant(
        of: find.byType(ProviderProfileFormSheet),
        matching: find.byType(ElevatedButton),
      );
      await tester.ensureVisible(save.last);
      await settle(tester);
      await tester.tap(save.last);
      await settle(tester);

      expect(api.count('PUT /api/provider/me'), 1);
      // Saved in the international format, as typed digits.
      expect(api.provider!['phone'], '+77055555555');
      await scrollTo(tester, number());
      expect(tester.widget<Text>(number()).data, '+77055555555');
      await scrollTo(tester, find.byKey(const ValueKey('service-name')));
      expect(find.text('Черновик'), findsOneWidget);
      // The number belongs to the business, not to the service.
      expect(api.count('POST /api/provider/me/listings'), 0);
    });
  });

  group('new restaurant', () {
    Future<void> openRestaurant(WidgetTester tester) async {
      await openCreate(tester, tile: 0);
      expect(find.text('Новый ресторан'), findsOneWidget);
    }

    testWidgets(
      'its own fields: address, map point, phone; no price or business card',
      (tester) async {
        await pump(tester, providerPhone: '+7 701 111 22 33');
        await openRestaurant(tester);
        expect(
          find.descendant(
            of: categoryCard(),
            matching: find.text('Рестораны и локации'),
          ),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('service-price')), findsNothing);
        expect(
          find.byKey(const ValueKey('service-business-phone')),
          findsNothing,
        );
        await scrollTo(
          tester,
          find.byKey(const ValueKey('restaurant-address')),
        );
        await scrollTo(
          tester,
          find.byKey(const ValueKey('restaurant-map-point')),
        );

        final phone = find.byKey(const ValueKey('restaurant-phone'));
        await scrollTo(tester, phone);
        expect(
          tester.widget<TextField>(phone).controller!.text,
          '+7 701 111 22 33',
        );
        expect(
          find.text('Необязательно. Номер будет виден клиентам'),
          findsOneWidget,
        );
        final city = find.byKey(const ValueKey('service-city'));
        await scrollTo(tester, city);
        expect(
          find.descendant(of: city, matching: find.text('Астана')),
          findsOneWidget,
        );
      },
    );

    testWidgets('the map point and address are saved', (tester) async {
      LocationPickerScreen.debugMapBuilder = (point, onPick) => TextButton(
        key: const ValueKey('fake-map'),
        onPressed: () => onPick(const LatLng(43.1, 76.9)),
        child: Text('$point'),
      );
      addTearDown(() => LocationPickerScreen.debugMapBuilder = null);
      final (api, _, _) = await pump(tester);
      await openRestaurant(tester);
      await enter(tester, 'service-name', 'Тест Холл');
      await enter(tester, 'restaurant-address', 'ул. Абая, 1');
      final point = find.byKey(const ValueKey('restaurant-map-point'));
      await scrollTo(tester, point);
      await tester.tap(point);
      await settle(tester);

      final confirm = find.byKey(const ValueKey('location-picker-confirm'));
      expect(tester.widget<ElevatedButton>(confirm).onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('fake-map')));
      await settle(tester);
      await tester.tap(confirm);
      await settle(tester);
      await scrollTo(tester, point);
      expect(find.text('Точка: 43.10000, 76.90000'), findsOneWidget);

      await scrollTo(tester, submit());
      await tester.tap(submit());
      await settle(tester);
      final body = lastCreateBody(api);
      expect(body['address'], 'ул. Абая, 1');
      expect(body['latitude'], 43.1);
      expect(body['longitude'], 76.9);
    });

    testWidgets('saves as venues, then opens halls and menus management', (
      tester,
    ) async {
      final (api, _, _) = await pump(tester);
      await openRestaurant(tester);
      await enter(tester, 'service-name', 'Тест Холл');
      await enter(tester, 'restaurant-phone', '+7 777 000 00 01');
      await scrollTo(tester, submit());
      expect(find.text('Опубликовать услугу'), findsNothing);
      expect(find.text('Опубликовать ресторан'), findsOneWidget);
      await tester.tap(submit());
      await settle(tester);

      final body = lastCreateBody(api);
      expect(
        body['category_id'],
        _categories.firstWhere((c) => c.slug == 'venues').id,
      );
      expect(body['name_ru'], 'Тест Холл');
      expect(body['city'], 'Астана');
      expect(body['phone'], '+7 777 000 00 01');
      expect(body['price'], 0);
      expect(
        body.containsKey('user_id'),
        isFalse,
      ); // the owner comes from the JWT
      expect(api.count('POST /api/provider/me/listings'), 1);
      expect(find.byType(RestaurantManageScreen), findsOneWidget);
      expect(find.byType(ProviderServiceFormScreen), findsNothing);
    });

    testWidgets('optional price and guests are saved; the look has defaults', (
      tester,
    ) async {
      final (api, _, _) = await pump(tester);
      await openRestaurant(tester);
      await enter(tester, 'service-name', 'Тест Холл');
      await enter(tester, 'restaurant-price', '150000');
      await enter(tester, 'restaurant-min-guests', '50');
      await enter(tester, 'restaurant-max-guests', '300');
      await scrollTo(tester, submit());
      await tester.tap(submit());
      await settle(tester);
      final body = lastCreateBody(api);
      expect(body['price'], 150000);
      expect(body['min_guests'], 50);
      expect(body['max_guests'], 300);
      expect(body['emoji'], '✨');
      expect(body['color_from'], '#3a1420');
      expect(body['color_to'], '#d4af6a');
    });

    testWidgets('price and guests stay optional', (tester) async {
      final (api, _, _) = await pump(tester);
      await openRestaurant(tester);
      await enter(tester, 'service-name', 'Тест Холл');
      await scrollTo(tester, submit());
      await tester.tap(submit());
      await settle(tester);
      final body = lastCreateBody(api);
      expect(body['price'], 0);
      expect(body['min_guests'], 0);
      expect(find.byType(RestaurantManageScreen), findsOneWidget);
    });

    testWidgets('a name is required, and nothing is sent without it', (
      tester,
    ) async {
      final (api, _, _) = await pump(tester);
      await openRestaurant(tester);
      await scrollTo(tester, submit());
      await tester.tap(submit());
      await settle(tester);
      expect(api.count('POST /api/provider/me/listings'), 0);
      expect(find.byType(ProviderServiceFormScreen), findsOneWidget);
    });
  });

  testWidgets('validation: errors next to the fields, nothing sent', (
    tester,
  ) async {
    final (api, _, _) = await pump(
      tester,
      withListing: false,
      providerCity: '',
    );
    await openCreate(tester);
    await tester.tap(submit());
    await settle(tester);
    expect(find.byType(ProviderServiceFormScreen), findsOneWidget);
    expect(find.text('Укажите название'), findsOneWidget);
    expect(find.text('Укажите цену числом'), findsOneWidget);
    await scrollTo(tester, find.byKey(const ValueKey('service-city')));
    expect(find.text('Выберите город'), findsWidgets);
    expect(api.count('POST /api/provider/me/listings'), 0);

    await enter(tester, 'service-name', 'Ведущий');
    expect(find.text('Укажите название'), findsNothing);
  });

  group('one category list', () {
    testWidgets('«Добавить услугу» lists every category from the API once', (
      tester,
    ) async {
      await pump(tester, withListing: false);
      await tester.tap(find.byKey(const ValueKey('my-services-add')));
      await settle(tester);
      expect(find.byType(ServicesCategoryTile), findsNWidgets(3));
      expect(find.text('Рестораны и локации'), findsOneWidget);
      expect(find.text('Ведущие'), findsOneWidget);
      expect(find.text('Артисты и исполнители'), findsOneWidget);
    });

    testWidgets('closing the list opens no form and sends nothing', (
      tester,
    ) async {
      final (api, _, _) = await pump(tester, withListing: false);
      await tester.tap(find.byKey(const ValueKey('my-services-add')));
      await settle(tester);
      await tester.tapAt(const Offset(10, 10));
      await settle(tester);
      expect(find.byType(ServicesCategoryTile), findsNothing);
      expect(find.byType(ProviderServiceFormScreen), findsNothing);
      expect(api.count('POST /api/provider/me/listings'), 0);
    });

    testWidgets('an ordinary category opens the ordinary form', (tester) async {
      await pump(tester, withListing: false);
      await openCreate(tester);
      expect(find.text('Новая услуга'), findsOneWidget);
      await scrollTo(tester, find.byKey(const ValueKey('service-price')));
      await scrollTo(
        tester,
        find.byKey(const ValueKey('service-business-phone')),
      );
      expect(find.byKey(const ValueKey('restaurant-address')), findsNothing);
      expect(find.byKey(const ValueKey('restaurant-phone')), findsNothing);
    });

    testWidgets('switching category swaps the fields and keeps the typing', (
      tester,
    ) async {
      final (api, _, _) = await pump(tester, withListing: false);
      await openCreate(tester);
      await enter(tester, 'service-name', 'Черновик');
      await enter(tester, 'service-price', '45000');

      await scrollTo(tester, categoryCard());
      await tester.tap(categoryCard());
      await settle(tester);
      await tester.tap(find.byType(ServicesCategoryTile).at(0));
      await settle(tester);
      expect(find.text('Новый ресторан'), findsOneWidget);
      expect(find.byKey(const ValueKey('service-price')), findsNothing);
      await enter(tester, 'restaurant-address', 'ул. Абая, 1');
      await scrollTo(tester, find.byKey(const ValueKey('service-name')));
      expect(find.text('Черновик'), findsOneWidget);

      await scrollTo(tester, categoryCard());
      await tester.tap(categoryCard());
      await settle(tester);
      await tester.tap(find.byType(ServicesCategoryTile).at(2));
      await settle(tester);
      expect(
        find.descendant(
          of: categoryCard(),
          matching: find.text('Артисты и исполнители'),
        ),
        findsOneWidget,
      );
      final price = find.byKey(const ValueKey('service-price'));
      await scrollTo(tester, price);
      expect(tester.widget<TextField>(price).controller!.text, '45000');

      // What only the restaurant's form showed isn't sent with a service.
      await scrollTo(tester, submit());
      await tester.tap(submit());
      await settle(tester);
      final body = lastCreateBody(api);
      expect(body['category_id'], 4);
      expect(body['price'], 45000);
      expect(body['address'], '');
      expect(body['phone'], '');
    });

    testWidgets('a price typed for a service stays visible on a restaurant', (
      tester,
    ) async {
      final (api, _, _) = await pump(tester, withListing: false);
      await openCreate(tester);
      await enter(tester, 'service-name', 'Черновик');
      await enter(tester, 'service-price', '45000');
      await scrollTo(tester, categoryCard());
      await tester.tap(categoryCard());
      await settle(tester);
      await tester.tap(find.byType(ServicesCategoryTile).at(0));
      await settle(tester);
      final price = find.byKey(const ValueKey('restaurant-price'));
      await scrollTo(tester, price);
      expect(tester.widget<TextField>(price).controller!.text, '45000');
      await scrollTo(tester, submit());
      await tester.tap(submit());
      await settle(tester);
      expect(lastCreateBody(api)['price'], 45000);
    });
  });

  group('what an owner edits next to the admin', () {
    Map<dynamic, dynamic> lastPut(ProviderFakeApi api, int id) =>
        api.bodies['PUT /api/listings/$id']!.last! as Map;

    Future<void> saveEdit(WidgetTester tester) async {
      await tester.tap(submit());
      await settle(tester);
    }

    testWidgets('the form keeps what an admin saved after it was opened', (
      tester,
    ) async {
      final (api, _, _) = await pump(tester);
      final old = _listing(101);
      api.listings.first.addAll({
        'video_urls': ['/uploads/v.mp4'],
        'phone': '+77770000000',
        'emoji': 'X',
        'min_guests': 5,
        'max_guests': 50,
      });

      await openEdit(tester, old);
      await enter(tester, 'service-name', 'Новое имя');
      await saveEdit(tester);

      final body = lastPut(api, 101);
      expect(body['name_ru'], 'Новое имя');
      expect(body['video_urls'], ['/uploads/v.mp4']);
      expect(body['phone'], '+77770000000');
      expect(body['emoji'], 'X');
      expect(body['min_guests'], 5);
      expect(body['max_guests'], 50);
    });

    testWidgets('nothing is saved when the current service can\'t be read', (
      tester,
    ) async {
      final (api, _, _) = await pump(tester);
      await openEdit(tester, _listing(101));
      api.failWith500['GET /api/listings/101'] = 1;
      await enter(tester, 'service-name', 'Новое имя');
      await saveEdit(tester);

      expect(api.bodies['PUT /api/listings/101'], isNull);
      expect(find.byType(ProviderServiceFormScreen), findsOneWidget);
    });

    testWidgets('hiding from the list keeps an admin\'s newer edits', (
      tester,
    ) async {
      final (api, _, _) = await pump(tester);
      api.listings.first.addAll({
        'name_ru': 'Правка админа',
        'video_urls': ['/uploads/v.mp4'],
      });
      await tester.tap(find.byKey(const ValueKey('service-status-101')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('hide-service-confirm')));
      await settle(tester);

      final body = lastPut(api, 101);
      expect(body['is_active'], isFalse);
      expect(body['name_ru'], 'Правка админа');
      expect(body['video_urls'], ['/uploads/v.mp4']);
    });

    testWidgets('a description over 2000 characters survives an edit', (
      tester,
    ) async {
      final (api, _, _) = await pump(tester);
      final long = 'а' * 2500;
      final listing = {
        ..._listing(101),
        'description_ru': long,
        'description_kz': 'қ' * 2300,
      };
      api.listings
        ..clear()
        ..add(listing);
      await openEdit(tester, listing);
      await enter(tester, 'service-description', 'б${long.substring(1)}');
      await saveEdit(tester);

      final body = lastPut(api, 101);
      expect((body['description_ru'] as String).length, 2500);
      expect((body['description_ru'] as String)[0], 'б');
      expect((body['description_kz'] as String).length, 2300);
    });

    testWidgets('a negotiable price needs no number; others still do', (
      tester,
    ) async {
      final (api, _, _) = await pump(tester);
      await openCreate(tester);
      await enter(tester, 'service-name', 'Договорная');
      await tester.tap(submit());
      await settle(tester);
      expect(find.text('Укажите цену числом'), findsOneWidget);
      expect(api.count('POST /api/provider/me/listings'), 0);

      final pill = find.byKey(const ValueKey('price-type-negotiable'));
      await scrollTo(tester, pill);
      await tester.tap(pill);
      await settle(tester);
      expect(find.text('Укажите цену числом'), findsNothing);
      expect(find.text('Цена, необязательно'), findsOneWidget);
      await tester.tap(submit());
      await settle(tester);

      final body = lastCreateBody(api);
      expect(body['price'], 0);
      expect(body['price_type'], 'negotiable');
    });

    for (final dark in [false, true]) {
      for (final locale in AppLocale.values) {
        testWidgets(
          'optional price fits: ${dark ? 'dark' : 'light'} · ${locale.name}',
          (tester) async {
            await pump(
              tester,
              size: const Size(320, 700),
              theme: dark ? () => AppTheme.dark : () => AppTheme.light,
              locale: locale,
            );
            await openCreate(tester);
            final pill = find.byKey(const ValueKey('price-type-negotiable'));
            await scrollTo(tester, pill);
            await tester.tap(pill);
            await settle(tester);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });

  group('editing and changing the category', () {
    Map<dynamic, dynamic> lastPut(ProviderFakeApi api, int id) =>
        api.bodies['PUT /api/listings/$id']!.last! as Map;

    testWidgets('a restaurant shows its saved category and its own fields', (
      tester,
    ) async {
      final (api, _, _) = await pump(tester);
      final saved = restaurant(200);
      api.listings.add(saved);
      await openEdit(tester, saved);
      expect(find.text('Изменить ресторан'), findsOneWidget);
      expect(
        find.descendant(
          of: categoryCard(),
          matching: find.text('Рестораны и локации'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('service-price')), findsNothing);
      final address = find.byKey(const ValueKey('restaurant-address'));
      await scrollTo(tester, address);
      expect(tester.widget<TextField>(address).controller!.text, 'ул. Абая, 1');
      final phone = find.byKey(const ValueKey('restaurant-phone'));
      await scrollTo(tester, phone);
      expect(
        tester.widget<TextField>(phone).controller!.text,
        '+7 777 123 45 67',
      );

      await scrollTo(tester, submit());
      await tester.tap(submit());
      await settle(tester);
      expect(find.byType(ProviderServiceFormScreen), findsNothing);
      final body = lastPut(api, 200);
      expect(body['category_id'], 1);
      expect(body['price'], 5000); // no field for it here, and not reset
      expect(body['latitude'], 43.25);
      expect(body['min_guests'], 20);
      expect(body['capacity'], 300);
    });

    for (final child in ['halls', 'menus']) {
      testWidgets('a restaurant with $child keeps its category', (
        tester,
      ) async {
        final (api, _, _) = await pump(tester);
        final saved = restaurant(200);
        api.listings.add(saved);
        (child == 'halls' ? api.halls : api.menus)[200] = [
          {'id': 1, 'listing_id': 200, 'name_ru': 'Зал', 'name_kz': 'Зал'},
        ];
        await openEdit(tester, saved);
        expect(
          find.byKey(const ValueKey('service-category-locked')),
          findsOneWidget,
        );
        await tester.tap(categoryCard(), warnIfMissed: false);
        await settle(tester);
        expect(find.byType(ServicesCategoryTile), findsNothing);
      });
    }

    testWidgets('if the halls can\'t be checked, the category stays locked', (
      tester,
    ) async {
      final (api, _, _) = await pump(tester);
      final saved = restaurant(200);
      api.listings.add(saved);
      api.failListingChildren = true;
      await openEdit(tester, saved);
      await tester.tap(categoryCard(), warnIfMissed: false);
      await settle(tester);
      expect(find.byType(ServicesCategoryTile), findsNothing);
    });

    testWidgets(
      'editing shows price and guests, and a moved point drops the place',
      (tester) async {
        LocationPickerScreen.debugMapBuilder = (point, onPick) => TextButton(
          key: const ValueKey('fake-map'),
          onPressed: () => onPick(const LatLng(43.3, 76.8)),
          child: const Text('map'),
        );
        addTearDown(() => LocationPickerScreen.debugMapBuilder = null);
        final (api, _, _) = await pump(tester);
        final saved = {...restaurant(200), 'place_id': 'old-place'};
        api.listings.add(saved);
        await openEdit(tester, saved);
        for (final (key, value) in [
          ('restaurant-price', '5000'),
          ('restaurant-min-guests', '20'),
          ('restaurant-max-guests', '300'),
        ]) {
          final field = find.byKey(ValueKey(key));
          await scrollTo(tester, field);
          expect(tester.widget<TextField>(field).controller!.text, value);
        }
        await scrollTo(tester, submit());
        await tester.tap(submit());
        await settle(tester);
        expect(lastPut(api, 200)['place_id'], 'old-place'); // point unchanged

        await openEdit(tester, Map<String, dynamic>.from(api.listings.last));
        final point = find.byKey(const ValueKey('restaurant-map-point'));
        await scrollTo(tester, point);
        await tester.tap(point);
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('fake-map')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('location-picker-confirm')));
        await settle(tester);
        await scrollTo(tester, submit());
        await tester.tap(submit());
        await settle(tester);
        expect(lastPut(api, 200)['latitude'], 43.3);
        expect(lastPut(api, 200)['place_id'], '');
      },
    );

    testWidgets('a city outside the directory is kept when editing', (
      tester,
    ) async {
      final (api, _, _) = await pump(tester);
      final saved = {...restaurant(200), 'city': 'Капчагай'};
      api.listings.add(saved);
      await openEdit(tester, saved);
      await scrollTo(tester, submit());
      await tester.tap(submit());
      await settle(tester);
      expect(lastPut(api, 200)['city'], 'Капчагай');
    });

    testWidgets('an empty restaurant can become a service, keeping its data', (
      tester,
    ) async {
      final (api, _, _) = await pump(tester);
      final saved = restaurant(200);
      api.listings.add(saved);
      await openEdit(tester, saved);
      await tester.tap(categoryCard());
      await settle(tester);
      await tester.tap(find.byType(ServicesCategoryTile).at(1));
      await settle(tester);
      expect(find.text('Изменить услугу'), findsOneWidget);
      final price = find.byKey(const ValueKey('service-price'));
      await scrollTo(tester, price);
      expect(tester.widget<TextField>(price).controller!.text, '5000');

      await scrollTo(tester, submit());
      await tester.tap(submit());
      await settle(tester);
      final body = lastPut(api, 200);
      expect(body['category_id'], 2);
      expect(body['price'], 5000);
      expect(body['address'], 'ул. Абая, 1');
      expect(body['phone'], '+7 777 123 45 67');
      expect(body['latitude'], 43.25);
      expect(body['longitude'], 76.95);
      expect(find.byType(RestaurantManageScreen), findsNothing);
    });

    testWidgets(
      'a service that becomes a restaurant goes on to its management',
      (tester) async {
        final (api, _, _) = await pump(tester);
        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey('my-service-101')),
            matching: find.text('Проведение тоя'),
          ),
        );
        await settle(tester);
        await scrollTo(tester, categoryCard());
        await tester.tap(categoryCard());
        await settle(tester);
        await tester.tap(find.byType(ServicesCategoryTile).at(0));
        await settle(tester);
        await enter(tester, 'restaurant-address', 'ул. Абая, 1');
        await scrollTo(tester, submit());
        await tester.tap(submit());
        await settle(tester);
        final body = lastPut(api, 101);
        expect(body['category_id'], 1);
        expect(body['price'], 150000); // kept for the case it changes back
        expect(body['address'], 'ул. Абая, 1');
        expect(find.byType(RestaurantManageScreen), findsOneWidget);
      },
    );

    testWidgets(
      '«Основное» shows the category and picks up the form\'s edits',
      (tester) async {
        final (api, _, _) = await pump(tester);
        api.listings.add({
          ...restaurant(200),
          'category': {
            'id': 1,
            'slug': 'venues',
            'name_ru': 'Рестораны и локации',
            'name_kz': 'Мейрамханалар',
          },
        });
        Navigator.of(tester.element(find.byType(MyServicesScreen))).push(
          MaterialPageRoute<void>(
            builder: (_) => const RestaurantManageScreen(listingId: 200),
          ),
        );
        await settle(tester);
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('basic-info-category')))
              .data,
          'Рестораны и локации',
        );
        await tester.tap(find.byKey(const ValueKey('basic-info-open-form')));
        await settle(tester);
        expect(find.text('Изменить ресторан'), findsOneWidget);
        await enter(tester, 'service-name', 'Алтын Новый');
        await scrollTo(tester, submit());
        await tester.tap(submit());
        await settle(tester);
        expect(find.byType(ProviderServiceFormScreen), findsNothing);
        expect(find.byType(RestaurantManageScreen), findsOneWidget);
        expect(find.widgetWithText(TextFormField, 'Алтын Новый'), findsWidgets);
      },
    );
  });

  testWidgets('city picker: directory sheet, global filter untouched', (
    tester,
  ) async {
    final (_, _, container) = await pump(tester);
    await openCreate(tester);
    final card = find.byKey(const ValueKey('service-city'));
    await scrollTo(tester, card);
    await tester.tap(card);
    await settle(tester);
    expect(find.byType(CitySheet), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(CitySheet),
        matching: find.text('Все города'),
      ),
      findsNothing,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(CitySheet),
        matching: find.text('Караганда'),
      ),
    );
    await settle(tester);
    expect(
      find.descendant(of: card, matching: find.text('Караганда')),
      findsOneWidget,
    );
    expect(container.read(selectedCityIdProvider), isNull);
  });

  group('checking picked photos before upload', () {
    Future<void> openCheck(WidgetTester tester) async {
      await openCreate(tester);
      await enter(tester, 'service-name', 'Фото');
      final add = find.byKey(const ValueKey('service-add-photo'));
      await scrollTo(tester, add);
      await tester.tap(add);
      await settle(tester);
    }

    testWidgets('nothing uploads until confirmed; a removed one never does', (
      tester,
    ) async {
      final (_, uploads, _) = await pump(tester);
      await openCheck(tester);
      expect(find.text('Выбрано фото: 3'), findsOneWidget);
      expect(uploads.calls, isEmpty);
      for (var i = 0; i < 3; i++) {
        expect(find.byKey(ValueKey('picked-photo-$i')), findsOneWidget);
      }

      await tester.tap(find.byKey(const ValueKey('picked-photo-remove-1')));
      await settle(tester);
      expect(find.text('Выбрано фото: 2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('picked-photos-confirm')));
      await settle(tester);
      expect(uploads.calls.single, hasLength(2));
      expect(uploads.calls.single.first, endsWith('p0.jpg'));
      expect(uploads.calls.single.last, endsWith('p2.jpg'));
    });

    testWidgets('cancelling uploads nothing and adds nothing', (tester) async {
      final (_, uploads, _) = await pump(tester);
      await openCheck(tester);
      await tester.tap(find.byKey(const ValueKey('picked-photos-cancel')));
      await settle(tester);
      expect(uploads.calls, isEmpty);
      expect(find.byKey(const ValueKey('service-photo-0')), findsNothing);
    });

    testWidgets('closing the check does not bring the keyboard back', (
      tester,
    ) async {
      await pump(tester);
      await openCheck(tester);
      await tester.tap(find.byKey(const ValueKey('picked-photos-cancel')));
      await settle(tester);
      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('removing all leaves nothing to confirm', (tester) async {
      final (_, uploads, _) = await pump(tester);
      await openCheck(tester);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const ValueKey('picked-photo-remove-0')));
        await settle(tester);
      }
      expect(
        tester
            .widget<ElevatedButton>(
              find.byKey(const ValueKey('picked-photos-confirm')),
            )
            .onPressed,
        isNull,
      );
      expect(uploads.calls, isEmpty);
    });

    for (final dark in [false, true]) {
      for (final width in [320.0, 430.0]) {
        for (final locale in AppLocale.values) {
          testWidgets(
            'no overflow: ${dark ? 'dark' : 'light'} · ${width.toInt()} · ${locale.name}',
            (tester) async {
              await pump(
                tester,
                size: Size(width, 700),
                theme: dark ? () => AppTheme.dark : () => AppTheme.light,
                locale: locale,
                withListing: false,
              );
              await openCreate(tester);
              final add = find.byKey(const ValueKey('service-add-photo'));
              await scrollTo(tester, add);
              await tester.tap(add);
              await settle(tester);
              expect(tester.takeException(), isNull);
              expect(
                find.byKey(const ValueKey('picked-photos-confirm')),
                findsOneWidget,
              );
            },
          );
        }
      }
    }
  });

  testWidgets('photos: delete and long-press reorder change what is saved', (
    tester,
  ) async {
    final (api, _, _) = await pump(tester);
    await openCreate(tester);
    await enter(tester, 'service-name', 'Фото');
    await enter(tester, 'service-price', '0');
    await scrollTo(tester, find.byKey(const ValueKey('service-add-photo')));
    await addPhotos(tester);
    await settle(tester);
    // f0, f1, f2 → remove f1 → f0, f2.
    await tester.tap(find.byKey(const ValueKey('service-photo-remove-1')));
    await settle(tester);
    // Drag the second (f2) onto the first.
    final from = tester.getCenter(
      find.byKey(const ValueKey('service-photo-1')),
    );
    final to = tester.getCenter(find.byKey(const ValueKey('service-photo-0')));
    final g = await tester.startGesture(from);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await g.moveTo(to);
    await tester.pump();
    await g.up();
    await settle(tester);

    await tester.tap(submit());
    await settle(tester);
    expect(lastCreateBody(api)['image_urls'], [
      '/uploads/f2.jpg',
      '/uploads/f0.jpg',
    ]);
  });

  testWidgets('photo upload: loading blocks save; failure → retry', (
    tester,
  ) async {
    final (api, uploads, _) = await pump(tester, pickedPhotos: tempPhotos(1));
    await openCreate(tester);
    await enter(tester, 'service-name', 'Фото');
    await enter(tester, 'service-price', '1000');

    uploads.gate = Completer<void>();
    await scrollTo(tester, find.byKey(const ValueKey('service-add-photo')));
    await addPhotos(tester);
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('service-photo-uploading-0')),
      findsOneWidget,
    );
    expect(tester.widget<ElevatedButton>(submit()).onPressed, isNull);
    expect(find.text('Дождитесь загрузки фото'), findsOneWidget);

    uploads.failNext = 1;
    uploads.gate!.complete();
    uploads.gate = null;
    await settle(tester);
    expect(find.byKey(const ValueKey('service-photo-retry-0')), findsOneWidget);
    await tester.tap(submit());
    await settle(tester);
    expect(api.count('POST /api/provider/me/listings'), 0);
    expect(
      find.text('Некоторые фото не загрузились — повторите или удалите их'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('service-photo-retry-0')));
    await settle(tester);
    expect(find.byKey(const ValueKey('service-photo-retry-0')), findsNothing);
    await tester.tap(submit());
    await settle(tester);
    expect(api.count('POST /api/provider/me/listings'), 1);
  });

  testWidgets('saving: spinner, and a double tap sends one request', (
    tester,
  ) async {
    final (api, _, _) = await pump(tester);
    await openCreate(tester);
    await enter(tester, 'service-name', 'Двойной');
    await enter(tester, 'service-price', '1000');
    api.createGate = Completer<void>();

    await tester.tap(submit());
    await tester.pump();
    await tester.tap(submit(), warnIfMissed: false);
    await tester.pump();
    expect(
      find.descendant(
        of: submit(),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    api.createGate!.complete();
    await settle(tester);
    expect(api.count('POST /api/provider/me/listings'), 1);
    expect(find.byType(ProviderServiceFormScreen), findsNothing);
  });

  testWidgets('edit: tap the service → everything prefilled → save changes', (
    tester,
  ) async {
    final (api, _, _) = await pump(tester);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('my-service-101')),
        matching: find.text('Проведение тоя'),
      ),
    );
    await settle(tester);
    expect(find.text('Изменить услугу'), findsOneWidget);
    expect(find.text('Сохранить изменения'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Проведение тоя'), findsOneWidget);
    expect(find.widgetWithText(TextField, '150000'), findsOneWidget);
    await scrollTo(tester, find.byKey(const ValueKey('service-category')));
    expect(find.text('Ведущие'), findsOneWidget);
    await scrollTo(tester, find.byKey(const ValueKey('service-city')));
    expect(find.text('Алматы'), findsOneWidget);
    await scrollTo(tester, find.byKey(const ValueKey('service-photo-1')));
    expect(find.byKey(const ValueKey('service-photo-1')), findsOneWidget);
    await scrollTo(tester, find.byKey(const ValueKey('service-name-kz')));
    expect(find.widgetWithText(TextField, 'Той жүргізу'), findsOneWidget);

    await enter(tester, 'service-price', '175000');
    await tester.tap(submit());
    await settle(tester);

    expect(find.byType(ProviderServiceFormScreen), findsNothing);
    expect(find.text('Изменения сохранены'), findsOneWidget);
    final body = api.bodies['PUT /api/listings/101']!.single! as Map;
    expect(body['price'], 175000);
    expect(body['category_id'], 2);
    expect(body['city'], 'Алматы');
    expect(body['name_kz'], 'Той жүргізу');
    expect(body['price_type'], 'from');
    expect(body['image_urls'], ['/uploads/a.jpg', '/uploads/b.jpg']);
  });

  testWidgets('keyboard open: the CTA stays above it', (tester) async {
    await pump(tester, size: const Size(390, 760));
    await openCreate(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetViewInsets);
    await tester.tap(find.byKey(const ValueKey('service-name')));
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(tester.getRect(submit()).bottom, lessThanOrEqualTo(760 - 320));
  });

  group('no overflow', () {
    const titles = {
      AppLocale.ru: ('Новая услуга', 'Опубликовать услугу'),
      AppLocale.kz: ('Жаңа қызмет', 'Қызметті жариялау'),
      AppLocale.en: ('New service', 'Publish service'),
    };
    final themes = <(String, ThemeData Function())>[
      ('light', () => AppTheme.light),
      ('dark', () => AppTheme.dark),
    ];
    for (final theme in themes) {
      for (final width in [320.0, 390.0, 430.0]) {
        for (final locale in AppLocale.values) {
          testWidgets('${theme.$1} · ${width.toInt()} · ${locale.name}', (
            tester,
          ) async {
            await pump(
              tester,
              size: Size(width, 760),
              theme: theme.$2,
              locale: locale,
              withListing: false,
              providerCity: '',
            );
            await tester.tap(find.byKey(const ValueKey('my-services-add')));
            await settle(tester);
            expect(tester.takeException(), isNull); // the category list
            await tester.tap(find.byType(ServicesCategoryTile).at(1));
            await settle(tester);
            final (title, cta) = titles[locale]!;
            expect(find.text(title), findsOneWidget);
            expect(find.text(cta), findsOneWidget);
            // Errors visible + photos added: the busiest state.
            await tester.tap(submit());
            await settle(tester);
            await scrollTo(
              tester,
              find.byKey(const ValueKey('service-add-photo')),
            );
            await addPhotos(tester);
            await settle(tester);
            await scrollTo(
              tester,
              find.byKey(const ValueKey('service-description-kz')),
            );
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });

  group('restaurant form: no overflow', () {
    for (final dark in [false, true]) {
      for (final width in [320.0, 390.0, 430.0]) {
        for (final locale in AppLocale.values) {
          testWidgets(
            '${dark ? 'dark' : 'light'} · ${width.toInt()} · ${locale.name}',
            (tester) async {
              await pump(
                tester,
                size: Size(width, 760),
                theme: dark ? () => AppTheme.dark : () => AppTheme.light,
                locale: locale,
                withListing: false,
                providerCity: '',
              );
              await openCreate(tester, tile: 0);
              await tester.tap(submit());
              await settle(tester);
              await scrollTo(
                tester,
                find.byKey(const ValueKey('restaurant-map-point')),
              );
              await scrollTo(
                tester,
                find.byKey(const ValueKey('restaurant-phone')),
              );
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
  });

  group('visibility in the catalog', () {
    Finder status() => find.byKey(const ValueKey('service-status-101'));

    testWidgets('hiding asks first; Cancel keeps the service public', (
      tester,
    ) async {
      final (api, _, _) = await pump(tester);
      expect(find.text('Опубликовано'), findsOneWidget);
      await tester.tap(status());
      await settle(tester);
      expect(find.text('Скрыть услугу?'), findsOneWidget);
      await tester.tap(find.text('Отмена'));
      await settle(tester);
      expect(api.count('PUT /api/listings/101'), 0);
      expect(find.text('Опубликовано'), findsOneWidget);
    });

    testWidgets('confirmed hide sends is_active=false and says so', (
      tester,
    ) async {
      final (api, _, _) = await pump(tester);
      await tester.tap(status());
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('hide-service-confirm')));
      await settle(tester);
      expect(api.count('PUT /api/listings/101'), 1);
      expect(
        (api.bodies['PUT /api/listings/101']!.single as Map)['is_active'],
        isFalse,
      );
      expect(find.text('Скрыто — не видно клиентам'), findsOneWidget);

      // Publishing again needs no confirmation.
      await tester.tap(status());
      await settle(tester);
      expect(find.text('Скрыть услугу?'), findsNothing);
      expect(api.count('PUT /api/listings/101'), 2);
      expect(find.text('Опубликовано'), findsOneWidget);
    });
  });

  test(
    'a new service refreshes every cached catalog list, filtered too',
    () async {
      final (client, api) = fakeProviderApi(
        existingProvider: {
          'id': 5,
          'user_id': 1,
          'display_name': 'Dana',
          'city': 'Алматы',
          'status': 'active',
        },
      );
      final fetches = <String?, int>{};
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(client),
          for (final slug in [null, 'hosts'])
            listingsProvider(slug).overrideWith((ref) {
              fetches[slug] = (fetches[slug] ?? 0) + 1;
              return Future.value(const <Listing>[]);
            }),
        ],
      );
      addTearDown(container.dispose);
      final subs = [
        container.listen(listingsProvider(null), (_, _) {}),
        container.listen(listingsProvider('hosts'), (_, _) {}),
      ];
      addTearDown(() {
        for (final s in subs) {
          s.close();
        }
      });
      await container.read(listingsProvider(null).future);
      await container.read(listingsProvider('hosts').future);
      expect(fetches, {null: 1, 'hosts': 1});

      await container
          .read(providerActionsProvider)
          .createListing(
            categoryId: 2,
            nameRu: 'Новая услуга',
            nameKz: 'Новая услуга',
            city: 'Алматы',
            price: 50000,
          );
      await container.read(listingsProvider(null).future);
      await container.read(listingsProvider('hosts').future);
      expect(fetches, {null: 2, 'hosts': 2});
      expect(api.count('POST /api/provider/me/listings'), 1);
    },
  );
}
