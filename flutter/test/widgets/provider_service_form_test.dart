import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/models/category.dart';
import 'package:mereytoi_app/screens/profile/provider/my_services_screen.dart';
import 'package:mereytoi_app/screens/profile/provider/widgets/provider_service_form_sheet.dart';
import 'package:mereytoi_app/services/upload_service.dart';
import 'package:mereytoi_app/state/categories_provider.dart';
import 'package:mereytoi_app/state/city_provider.dart';
import 'package:mereytoi_app/state/locale_provider.dart';
import 'package:mereytoi_app/state/provider_onboarding.dart';
import 'package:mereytoi_app/state/providers.dart';
import 'package:mereytoi_app/widgets/city_selector.dart';
import 'package:mereytoi_app/widgets/services/services_category_grid.dart';
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

  Future<void> openCreate(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('my-services-add')));
    await settle(tester);
    expect(find.byType(ProviderServiceFormScreen), findsOneWidget);
  }

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

  Map<dynamic, dynamic> lastCreateBody(ProviderFakeApi api) =>
      api.bodies['POST /api/provider/me/listings']!.last! as Map;

  testWidgets(
    'create: prefilled city/category, photos, publish → closes, snackbar, list refreshed',
    (tester) async {
      final (api, uploads, _) = await pump(tester);
      await openCreate(tester);
      expect(find.text('Новая услуга'), findsOneWidget);
      expect(find.text('Опубликовать услугу'), findsOneWidget);
      // Defaults: the provider's latest category and the profile's city.
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
      await tester.tap(find.byKey(const ValueKey('service-add-photo')));
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
    expect(find.text('Выберите категорию'), findsWidgets);
    expect(find.text('Выберите город'), findsWidgets);
    expect(api.count('POST /api/provider/me/listings'), 0);

    await enter(tester, 'service-name', 'Ведущий');
    expect(find.text('Укажите название'), findsNothing);
  });

  testWidgets('category picker: same tiles, no venues, selection shown', (
    tester,
  ) async {
    await pump(tester, withListing: false);
    await openCreate(tester);
    final card = find.byKey(const ValueKey('service-category'));
    await scrollTo(tester, card);
    await tester.tap(card);
    await settle(tester);
    expect(find.text('Выберите категорию'), findsWidgets);
    expect(find.text('Рестораны и локации'), findsNothing);
    expect(find.byType(ServicesCategoryTile), findsNWidgets(2));
    await tester.tap(find.text('Артисты и исполнители'));
    await settle(tester);
    expect(
      find.descendant(of: card, matching: find.text('Артисты и исполнители')),
      findsOneWidget,
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

  testWidgets('photos: delete and long-press reorder change what is saved', (
    tester,
  ) async {
    final (api, _, _) = await pump(tester);
    await openCreate(tester);
    await enter(tester, 'service-name', 'Фото');
    await enter(tester, 'service-price', '0');
    await scrollTo(tester, find.byKey(const ValueKey('service-add-photo')));
    await tester.tap(find.byKey(const ValueKey('service-add-photo')));
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
    await tester.tap(find.byKey(const ValueKey('service-add-photo')));
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
            await tester.tap(find.byKey(const ValueKey('service-add-photo')));
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
}
