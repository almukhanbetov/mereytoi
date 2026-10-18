import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/core/utils/format.dart';
import 'package:mereytoi_app/models/category.dart';
import 'package:mereytoi_app/screens/profile/provider/my_services_screen.dart';
import 'package:mereytoi_app/screens/profile/provider/widgets/provider_service_form_sheet.dart';
import 'package:mereytoi_app/screens/provider/onboarding/provider_onboarding_screen.dart';
import 'package:mereytoi_app/screens/provider/onboarding/provider_onboarding_success_screen.dart';
import 'package:mereytoi_app/state/categories_provider.dart';
import 'package:mereytoi_app/state/city_provider.dart';
import 'package:mereytoi_app/state/locale_provider.dart';
import 'package:mereytoi_app/state/provider_onboarding.dart';
import 'package:mereytoi_app/services/upload_service.dart';
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
    nameKz: 'Мейрамханалар мен локациялар',
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
  Category(
    id: 9,
    slug: 'Interactiveequipment',
    nameRu: 'Интерактивное оборудование',
    nameKz: 'Интерактивті жабдық',
    position: 9,
  ),
];

class _FakeUploads extends UploadService {
  _FakeUploads(super.client);

  var _n = 0;

  @override
  Future<List<String>> uploadImages(List<String> filePaths) async => [
    for (final _ in filePaths) '/uploads/w${_n++}.jpg',
  ];
}

void main() {
  Future<ProviderFakeApi> pumpWizard(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    ThemeData Function()? theme,
    AppLocale locale = AppLocale.ru,
    Map<String, dynamic>? existingProvider,
  }) async {
    SharedPreferences.setMockInitialValues({
      if (locale != AppLocale.ru) 'app_locale_v1': locale.name,
    });
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (client, api) = fakeProviderApi(existingProvider: existingProvider);
    final photos = tempPhotos(2);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(client),
          categoriesProvider.overrideWith((ref) => Future.value(_categories)),
          citiesProvider.overrideWith((ref) => Future.value(testCities)),
          onboardingPhotoPickerProvider.overrideWithValue(() async => photos),
          // Real multipart uploads read the files with real IO, which never
          // completes inside testWidgets' fake async.
          uploadServiceProvider.overrideWithValue(_FakeUploads(client)),
        ],
        child: MaterialApp(
          theme: (theme ?? () => AppTheme.light)(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ProviderOnboardingScreen(),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return api;
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(ProviderOnboardingScreen)),
      );

  ProviderOnboardingState state(WidgetTester tester) =>
      containerOf(tester).read(providerOnboardingProvider);

  Finder next() => find.byKey(const ValueKey('onboarding-next'));
  Finder back() => find.byKey(const ValueKey('onboarding-back'));
  bool nextEnabled(WidgetTester tester) =>
      tester.widget<ElevatedButton>(next()).onPressed != null;
  String progress(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('onboarding-progress-label')))
      .data!;

  Future<void> tapNext(WidgetTester tester) async {
    await tester.tap(next());
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String key, String text) async {
    await tester.enterText(find.byKey(ValueKey(key)), text);
    await tester.pump();
  }

  testWidgets(
    'full flow 1→6, back keeps data, publish → success → Мои услуги',
    (tester) async {
      final api = await pumpWizard(tester);

      // Step 1 — category. Restaurants aren't offered here.
      expect(progress(tester), '1 из 6');
      expect(find.text('Чем вы занимаетесь?'), findsOneWidget);
      expect(find.text('Рестораны и локации'), findsNothing);
      expect(find.byType(ServicesCategoryTile), findsNWidgets(3));
      expect(nextEnabled(tester), isFalse);
      await tester.tap(find.text('Ведущие'));
      await tester.pump();
      expect(nextEnabled(tester), isTrue);
      await tapNext(tester);

      // Step 2 — about you, with experience validation.
      expect(progress(tester), '2 из 6');
      expect(find.text('Расскажите о себе'), findsOneWidget);
      expect(nextEnabled(tester), isFalse);
      await enter(tester, 'onboarding-name', 'Ерлан Тамада');
      await enter(tester, 'onboarding-description', 'Ведущий тоев');
      await enter(tester, 'onboarding-experience', '99');
      expect(find.text('От 0 до 80'), findsOneWidget);
      expect(nextEnabled(tester), isFalse);
      await enter(tester, 'onboarding-experience', '7');
      expect(find.text('От 0 до 80'), findsNothing);
      expect(nextEnabled(tester), isTrue);
      await tapNext(tester);

      // Step 3 — city via the directory picker, not the global filter.
      expect(progress(tester), '3 из 6');
      expect(nextEnabled(tester), isFalse);
      await tester.tap(find.byKey(const ValueKey('onboarding-city')));
      await tester.pumpAndSettle();
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
          matching: find.text('Алматы'),
        ),
      );
      await tester.pumpAndSettle();
      expect(state(tester).city?.id, 1);
      expect(containerOf(tester).read(selectedCityIdProvider), isNull);
      await tapNext(tester);

      // Step 4 — photos (optional): add, cover badge, remove.
      expect(progress(tester), '4 из 6');
      expect(find.text('Пока нет фото'), findsOneWidget);
      expect(nextEnabled(tester), isTrue);
      await tester.tap(find.byKey(const ValueKey('onboarding-add-photos')));
      await tester.pumpAndSettle();
      expect(state(tester).photos, hasLength(2));
      expect(find.text('Обложка'), findsOneWidget);
      await tapNext(tester);

      // Step 5 — first service; category & city carried over, not re-asked.
      expect(progress(tester), '5 из 6');
      expect(find.text('Создайте первую услугу'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(Wrap), matching: find.text('Ведущие')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(Wrap), matching: find.text('Алматы')),
        findsOneWidget,
      );
      expect(nextEnabled(tester), isFalse);
      await enter(tester, 'onboarding-service-name', 'Проведение тоя');
      expect(nextEnabled(tester), isFalse);
      await enter(tester, 'onboarding-price', '150000');
      expect(nextEnabled(tester), isTrue);
      await tapNext(tester);

      // Step 6 — preview.
      expect(progress(tester), '6 из 6');
      expect(find.text('Опубликовать'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('preview-meta'))).data,
        'Ведущие · Алматы · опыт 7 лет',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('preview-service-name')))
            .data,
        'Проведение тоя',
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('preview-price'))).data,
        formatPrice(150000),
      );

      // Back all the way: everything is still there.
      for (var i = 0; i < 5; i++) {
        await tester.tap(back());
        await tester.pumpAndSettle();
      }
      expect(progress(tester), '1 из 6');
      expect(
        tester
            .widget<ServicesCategoryTile>(
              find.widgetWithText(ServicesCategoryTile, 'Ведущие'),
            )
            .selected,
        isTrue,
      );
      await tapNext(tester);
      expect(find.widgetWithText(TextField, 'Ерлан Тамада'), findsOneWidget);
      expect(find.widgetWithText(TextField, '7'), findsOneWidget);
      await tapNext(tester);
      expect(find.text('Алматы'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await tapNext(tester);
      }
      expect(progress(tester), '6 из 6');

      // Publish.
      await tapNext(tester);
      expect(find.byType(ProviderOnboardingSuccessScreen), findsOneWidget);
      expect(find.text('Профиль создан'), findsOneWidget);
      expect(
        find.text('Теперь клиенты смогут найти ваши услуги'),
        findsOneWidget,
      );
      expect(api.count('POST /api/provider'), 1);
      expect(api.listings, hasLength(1));
      expect(api.listings.single['city'], 'Алматы');
      expect(api.listings.single['category_id'], 2);

      await tester.tap(find.byKey(const ValueKey('success-my-services')));
      // «Мои услуги» shows the new service's network photo, whose loading
      // placeholder keeps animating in tests — pump a fixed time instead.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(MyServicesScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('success «Добавить ещё услугу» opens Мои услуги with the form', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (client, _) = fakeProviderApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(client),
          categoriesProvider.overrideWith((ref) => Future.value(_categories)),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const ProviderOnboardingSuccessScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('success-add-service')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // The form is a full-screen route on top of «Мои услуги».
    expect(find.byType(MyServicesScreen, skipOffstage: false), findsOneWidget);
    expect(find.byType(ProviderServiceFormScreen), findsOneWidget);
  });

  testWidgets('system back steps back instead of closing', (tester) async {
    await pumpWizard(tester);
    await tester.tap(find.text('Ведущие'));
    await tester.pump();
    await tapNext(tester);
    expect(progress(tester), '2 из 6');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ProviderOnboardingScreen), findsOneWidget);
    expect(progress(tester), '1 из 6');
  });

  testWidgets('an existing provider is prefilled and updated, not duplicated', (
    tester,
  ) async {
    final api = await pumpWizard(
      tester,
      existingProvider: {
        'id': 5,
        'user_id': 1,
        'display_name': 'Dana Events',
        'city': 'Астана',
        'description': 'Ведущая',
        'experience_years': 3,
        'status': 'active',
      },
    );
    await tester.pumpAndSettle();
    expect(state(tester).existingProvider, isNotNull);
    expect(state(tester).displayName, 'Dana Events');
    expect(state(tester).city?.id, 2);

    final c = containerOf(tester).read(providerOnboardingProvider.notifier);
    c.selectCategory(4);
    c.setServiceName('Шоу');
    c.setPrice('90000');
    for (var i = 0; i < 5; i++) {
      c.next();
    }
    await tester.pumpAndSettle();
    expect(progress(tester), '6 из 6');
    await tapNext(tester);

    expect(find.byType(ProviderOnboardingSuccessScreen), findsOneWidget);
    expect(api.count('POST /api/provider'), 0);
    expect(api.count('PUT /api/provider/me'), 1);
    expect(api.listings.single['city'], 'Астана');
  });

  testWidgets('a failed publish shows a retry message; retry succeeds once', (
    tester,
  ) async {
    final api = await pumpWizard(tester);
    final c = containerOf(tester).read(providerOnboardingProvider.notifier);
    c.selectCategory(2);
    c.setDisplayName('Dana');
    c.setCity(testCities.first);
    c.setServiceName('Шоу');
    c.setPrice('1000');
    for (var i = 0; i < 5; i++) {
      c.next();
    }
    await tester.pumpAndSettle();
    api.failWith500['POST /api/provider/me/listings'] = 1;

    await tapNext(tester);
    expect(
      find.byKey(const ValueKey('onboarding-publish-error')),
      findsOneWidget,
    );
    expect(find.byType(ProviderOnboardingSuccessScreen), findsNothing);

    await tapNext(tester);
    expect(find.byType(ProviderOnboardingSuccessScreen), findsOneWidget);
    expect(api.count('POST /api/provider'), 1);
    expect(api.listings, hasLength(1));
  });

  // The step title must use a style the app theme defines (an undefined
  // Material headline style rendered white-on-light on the device).
  for (final (name, theme) in <(String, ThemeData Function())>[
    ('light', () => AppTheme.light),
    ('dark', () => AppTheme.dark),
  ]) {
    testWidgets('$name: step title is drawn in the theme text colour', (
      tester,
    ) async {
      await pumpWizard(tester, theme: theme);
      final title = tester.widget<Text>(find.text('Чем вы занимаетесь?'));
      final context = tester.element(find.text('Чем вы занимаетесь?'));
      expect(title.style?.color, context.mereytoiColors.textPrimary);
    });
  }

  group('no overflow on every step', () {
    const texts = {
      AppLocale.ru: ('1 из 6', 'Чем вы занимаетесь?', 'Предпросмотр'),
      AppLocale.kz: ('6 қадамның 1-і', 'Немен айналысасыз?', 'Алдын ала қарау'),
      AppLocale.en: ('1 of 6', 'What do you do?', 'Preview'),
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
            await pumpWizard(
              tester,
              size: Size(width, 720),
              theme: theme.$2,
              locale: locale,
            );
            final (step1, title1, preview) = texts[locale]!;
            expect(progress(tester), step1);
            expect(find.text(title1), findsOneWidget);
            expect(tester.takeException(), isNull);

            final c = containerOf(
              tester,
            ).read(providerOnboardingProvider.notifier);
            c.selectCategory(9); // longest category name
            c.setDisplayName(
              'Очень длинное название компании для проверки переносов строк',
            );
            c.setExperience('25');
            c.setCity(testCities[3]); // Усть-Каменогорск / Өскемен
            c.addPhotos(tempPhotos(3));
            c.setServiceName(
              'Проведение свадебного тоя с ведущим и музыкальной программой',
            );
            c.setPrice('123456789');
            for (var i = 0; i < 5; i++) {
              c.next();
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
            }
            expect(find.text(preview), findsOneWidget);
          });
        }
      }
    }
  });

  testWidgets('keyboard open on the profile step: CTA stays above it', (
    tester,
  ) async {
    await pumpWizard(tester, size: const Size(390, 760));
    await tester.tap(find.text('Ведущие'));
    await tester.pump();
    await tapNext(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetViewInsets);
    await tester.tap(find.byKey(const ValueKey('onboarding-name')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getRect(next()).bottom, lessThanOrEqualTo(760 - 320));
  });
}
