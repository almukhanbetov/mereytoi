import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/core/utils/format.dart';
import 'package:mereytoi_app/models/category.dart';
import 'package:mereytoi_app/models/event.dart';
import 'package:mereytoi_app/models/site_statistics.dart';
import 'package:mereytoi_app/models/user.dart';
import 'package:mereytoi_app/screens/auth/login_screen.dart';
import 'package:mereytoi_app/screens/home/home_screen.dart';
import 'package:mereytoi_app/screens/profile/profile_screen.dart';
import 'package:mereytoi_app/screens/profile/provider/my_services_screen.dart';
import 'package:mereytoi_app/screens/profile/provider/widgets/provider_profile_form_sheet.dart';
import 'package:mereytoi_app/screens/provider/business/my_business_screen.dart';
import 'package:mereytoi_app/screens/provider/business/provider_bookings_screen.dart';
import 'package:mereytoi_app/screens/provider/business/provider_statistics_screen.dart';
import 'package:mereytoi_app/screens/provider/onboarding/provider_onboarding_screen.dart';
import 'package:mereytoi_app/screens/provider_chat/provider_chat_list_screen.dart';
import 'package:mereytoi_app/state/auth_provider.dart';
import 'package:mereytoi_app/state/categories_provider.dart';
import 'package:mereytoi_app/state/event_providers.dart';
import 'package:mereytoi_app/state/listings_provider.dart';
import 'package:mereytoi_app/state/locale_provider.dart';
import 'package:mereytoi_app/state/provider_provider.dart';
import 'package:mereytoi_app/state/providers.dart';
import 'package:mereytoi_app/state/statistics_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/provider_fake_api.dart';

class _EmptySecureStoragePlatform extends FlutterSecureStoragePlatform {
  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) => Future.value(false);
  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {}
  @override
  Future<void> deleteAll({required Map<String, String> options}) async {}
  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) => Future.value(null);
  @override
  Future<Map<String, String>> readAll({required Map<String, String> options}) =>
      Future.value(const {});
  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {}
}

final _user = User(
  id: 9,
  name: 'Алия',
  email: 'aliya@example.com',
  phone: '+7 700 000 00 00',
  role: 'user',
  status: 'active',
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

const _categories = [
  Category(
    id: 1,
    slug: 'venues',
    nameRu: 'Рестораны',
    nameKz: 'Мейрамхана',
    position: 1,
  ),
  Category(
    id: 2,
    slug: 'hosts',
    nameRu: 'Ведущие',
    nameKz: 'Жүргізушілер',
    position: 2,
  ),
];

final _provider = <String, dynamic>{
  'id': 5,
  'user_id': 9,
  'display_name': 'Очень длинное название компании услугодателя для проверки',
  'city': 'Усть-Каменогорск',
  'experience_years': 7,
  'status': 'active',
};

Map<String, dynamic> _listing(int id, int categoryId) => {
  'id': id,
  'category_id': categoryId,
  'name_ru': 'Услуга $id',
  'name_kz': 'Қызмет $id',
  'price': 50000,
  'is_active': true,
};

final _bookings = <Map<String, dynamic>>[
  {
    'id': 31,
    'public_ref': 'abc',
    'status': 'new',
    'created_at': '2026-10-18T10:15:00Z',
    'event_date': '2027-06-12T00:00:00Z',
    'client_name': 'Клиент Айгерим',
    'client_phone': '+77001112233',
    'message': 'Здравствуйте, свободна ли дата?',
    'items': [
      {'listing_id': 101, 'title': 'Проведение тоя', 'total_price': 150000},
    ],
    'total': 150000,
  },
  {
    'id': 30,
    'public_ref': 'def',
    'status': 'confirmed',
    'created_at': '2026-10-17T09:00:00Z',
    'client_name': 'Клиент 2',
    'client_phone': '',
    'items': [
      {'listing_id': 101, 'title': 'Проведение тоя', 'total_price': 90000},
    ],
    'total': 90000,
  },
];

void main() {
  setUp(() {
    FlutterSecureStoragePlatform.instance = _EmptySecureStoragePlatform();
  });

  Future<(ProviderContainer, ProviderFakeApi)> pump(
    WidgetTester tester,
    Widget home, {
    bool signedIn = true,
    bool isProvider = false,
    List<Map<String, dynamic>> bookings = const [],
    Size size = const Size(390, 844),
    ThemeData Function()? theme,
    AppLocale locale = AppLocale.ru,
  }) async {
    SharedPreferences.setMockInitialValues({
      if (locale != AppLocale.ru) 'app_locale_v1': locale.name,
    });
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final (client, api) = fakeProviderApi(
      existingProvider: isProvider ? Map.of(_provider) : null,
    );
    if (isProvider) {
      api.listings
        ..add(_listing(101, 2))
        ..add(_listing(102, 1)); // a venue: not counted as a service
    }
    api.bookings.addAll(bookings);

    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        categoriesProvider.overrideWith((ref) => Future.value(_categories)),
        listingsProvider(null).overrideWith((ref) => Future.value(const [])),
        listingsProvider(
          'venues',
        ).overrideWith((ref) => Future.value(const [])),
        statisticsProvider.overrideWith(
          (ref) => Future.value(
            const SiteStatistics(
              eventsCount: 1,
              happyGuestsCount: 1,
              yearsExperience: 1,
              citiesCount: 1,
            ),
          ),
        ),
        eventsProvider.overrideWith((ref) => Future.value(const <Event>[])),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: (theme ?? () => AppTheme.light)(),
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
    while (container.read(authProvider) is AuthLoading ||
        container.read(authProvider) is AuthInitial) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    if (signedIn) {
      container.read(authProvider.notifier).state = AuthAuthenticated(_user);
      await tester.pumpAndSettle();
    }
    return (container, api);
  }

  Future<void> scrollTo(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(
      f,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    // Bring it fully on screen so a tap lands on it.
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
  }

  group('Home entry', () {
    testWidgets('guest: promo, CTA signs in first', (tester) async {
      await pump(tester, const HomeScreen(), signedIn: false);
      final cta = find.byKey(const ValueKey('provider-card-cta'));
      await scrollTo(tester, cta);
      expect(find.byKey(const ValueKey('provider-promo-card')), findsOneWidget);
      expect(find.text('Зарабатывайте вместе с MEREYTOI'), findsOneWidget);
      await tester.tap(cta);
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('non-provider: «Стать услугодателем» opens onboarding', (
      tester,
    ) async {
      await pump(tester, const HomeScreen());
      final cta = find.byKey(const ValueKey('provider-card-cta'));
      await scrollTo(tester, cta);
      expect(find.text('Стать услугодателем'), findsOneWidget);
      expect(find.text('Мой бизнес'), findsNothing);
      await tester.tap(cta);
      await tester.pumpAndSettle();
      expect(find.byType(ProviderOnboardingScreen), findsOneWidget);
    });

    testWidgets('provider: «Мой бизнес» with real counts, opens the hub', (
      tester,
    ) async {
      await pump(
        tester,
        const HomeScreen(),
        isProvider: true,
        bookings: _bookings,
      );
      final card = find.byKey(const ValueKey('provider-business-card'));
      await scrollTo(tester, card);
      expect(card, findsOneWidget);
      expect(find.text('Стать услугодателем'), findsNothing);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('provider-business-summary')),
            )
            .data,
        '1 услуга · 2 заявки',
      );
      await tester.tap(find.byKey(const ValueKey('provider-card-cta')));
      await tester.pumpAndSettle();
      expect(find.byType(MyBusinessScreen), findsOneWidget);
    });

    testWidgets('after onboarding publishes, Home switches without re-login', (
      tester,
    ) async {
      final (container, _) = await pump(tester, const HomeScreen());
      await scrollTo(tester, find.byKey(const ValueKey('provider-card-cta')));
      expect(find.byKey(const ValueKey('provider-promo-card')), findsOneWidget);

      // What the onboarding's publish does for the profile.
      // Dio completes on timers, which only run while the test pumps.
      final becoming = container
          .read(providerActionsProvider)
          .become(displayName: 'Dana Events', city: 'Алматы');
      await tester.pumpAndSettle();
      await becoming;
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('provider-business-card')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('provider-promo-card')), findsNothing);
      expect(container.read(authProvider), isA<AuthAuthenticated>());
    });
  });

  group('Profile entry', () {
    testWidgets('non-provider: only «Стать услугодателем»', (tester) async {
      await pump(tester, const ProfileScreen());
      await scrollTo(tester, find.text('Стать услугодателем'));
      expect(find.text('Стать услугодателем'), findsOneWidget);
      expect(find.text('Мой бизнес'), findsNothing);
    });

    testWidgets('provider: only «Мой бизнес», which opens the hub', (
      tester,
    ) async {
      await pump(tester, const ProfileScreen(), isProvider: true);
      final entry = find.byKey(const ValueKey('profile-my-business'));
      await scrollTo(tester, entry);
      expect(find.text('Мой бизнес'), findsOneWidget);
      expect(find.text('Стать услугодателем'), findsNothing);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.byType(MyBusinessScreen), findsOneWidget);
    });
  });

  group('My business', () {
    testWidgets('header: name, city, experience, status; counts on tiles', (
      tester,
    ) async {
      await pump(
        tester,
        const MyBusinessScreen(),
        isProvider: true,
        bookings: _bookings,
      );
      expect(find.text('Мой бизнес'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('business-meta'))).data,
        'Усть-Каменогорск · опыт 7 лет',
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('business-status'))).data,
        'Активен',
      );
      for (final title in [
        'Мои услуги',
        'Заявки',
        'Сообщения',
        'Профиль',
        'Статистика',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      expect(find.text('1 услуга'), findsOneWidget);
      expect(find.text('2 заявки'), findsOneWidget);
    });

    testWidgets('opening it re-fetches requests that arrived meanwhile', (
      tester,
    ) async {
      final (container, api) = await pump(
        tester,
        const Scaffold(body: SizedBox()),
        isProvider: true,
      );
      // Cache an empty list, then a request arrives on the server.
      final first = container.read(providerBookingsProvider.future);
      await tester.pumpAndSettle();
      expect(await first, isEmpty);
      api.bookings.add(_bookings.first);

      Navigator.of(
        tester.element(find.byType(SizedBox).first),
      ).push(MaterialPageRoute(builder: (_) => const MyBusinessScreen()));
      await tester.pumpAndSettle();
      expect(find.text('1 заявка'), findsOneWidget);
    });

    Future<void> openTile(WidgetTester tester, String key) async {
      final tile = find.byKey(ValueKey(key));
      await scrollTo(tester, tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();
    }

    testWidgets('Мои услуги → existing services screen', (tester) async {
      await pump(tester, const MyBusinessScreen(), isProvider: true);
      await openTile(tester, 'business-services');
      expect(find.byType(MyServicesScreen), findsOneWidget);
    });

    testWidgets('Заявки → real data from /provider/me/bookings', (
      tester,
    ) async {
      await pump(
        tester,
        const MyBusinessScreen(),
        isProvider: true,
        bookings: _bookings,
      );
      await openTile(tester, 'business-bookings');
      expect(find.byType(ProviderBookingsScreen), findsOneWidget);
      expect(find.text('Клиент Айгерим'), findsOneWidget);
      expect(find.text('+77001112233'), findsOneWidget);
      expect(find.text('Дата мероприятия: 12.06.2027'), findsOneWidget);
      expect(find.text('Новая'), findsOneWidget);
      expect(find.text('Подтверждена'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('booking-31-total')))
            .data,
        formatPrice(150000),
      );
    });

    testWidgets('Заявки: requests that arrived while on the hub show up', (
      tester,
    ) async {
      final (_, api) = await pump(
        tester,
        const MyBusinessScreen(),
        isProvider: true,
      );
      api.bookings.add(_bookings.first);
      await openTile(tester, 'business-bookings');
      expect(find.text('Клиент Айгерим'), findsOneWidget);
    });

    testWidgets('Заявки: «Итого» readable in the dark theme', (tester) async {
      await pump(
        tester,
        const MyBusinessScreen(),
        isProvider: true,
        bookings: [_bookings.first],
        theme: () => AppTheme.dark,
      );
      await openTile(tester, 'business-bookings');
      final total = find.text('Итого');
      expect(
        tester.widget<Text>(total).style?.color,
        tester.element(total).mereytoiColors.textPrimary,
      );
    });

    testWidgets('Заявки: empty state', (tester) async {
      await pump(tester, const MyBusinessScreen(), isProvider: true);
      await openTile(tester, 'business-bookings');
      expect(find.text('Пока нет заявок'), findsWidgets);
    });

    testWidgets('Сообщения → provider conversations', (tester) async {
      await pump(tester, const MyBusinessScreen(), isProvider: true);
      await openTile(tester, 'business-messages');
      expect(find.byType(ProviderChatListScreen), findsOneWidget);
    });

    testWidgets('Профиль → existing provider profile form', (tester) async {
      await pump(tester, const MyBusinessScreen(), isProvider: true);
      await openTile(tester, 'business-profile');
      expect(find.byType(ProviderProfileFormSheet), findsOneWidget);
    });

    testWidgets('Профиль: experience is editable and saved', (tester) async {
      final (_, api) = await pump(
        tester,
        const MyBusinessScreen(),
        isProvider: true,
      );
      await openTile(tester, 'business-profile');
      final field = find.byKey(const ValueKey('provider-profile-experience'));
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(field).controller!.text, '7');
      final save = find.text('Сохранить');

      await tester.enterText(field, '81');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('От 0 до 80'), findsOneWidget);
      expect(api.count('PUT /api/provider/me'), 0);

      await tester.enterText(field, '9');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(api.count('PUT /api/provider/me'), 1);
      expect(
        (api.bodies['PUT /api/provider/me']!.single as Map)['experience_years'],
        9,
      );
      expect(api.provider!['experience_years'], 9);
      expect(find.byType(ProviderProfileFormSheet), findsNothing);
    });

    testWidgets('Статистика → placeholder, no numbers', (tester) async {
      await pump(tester, const MyBusinessScreen(), isProvider: true);
      await openTile(tester, 'business-statistics');
      expect(find.byType(ProviderStatisticsScreen), findsOneWidget);
      expect(find.text('Статистика появится здесь'), findsOneWidget);
      final texts = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(ProviderStatisticsScreen),
              matching: find.byType(Text),
            ),
          )
          .map((t) => t.data ?? '');
      expect(texts.any((s) => RegExp(r'\d').hasMatch(s)), isFalse);
    });
  });

  group('no overflow', () {
    final themes = <(String, ThemeData Function())>[
      ('light', () => AppTheme.light),
      ('dark', () => AppTheme.dark),
    ];
    const titles = {
      AppLocale.ru: 'Мой бизнес',
      AppLocale.kz: 'Менің бизнесім',
      AppLocale.en: 'My business',
    };
    for (final theme in themes) {
      for (final width in [320.0, 390.0, 430.0]) {
        for (final locale in AppLocale.values) {
          testWidgets('${theme.$1} · ${width.toInt()} · ${locale.name}', (
            tester,
          ) async {
            await pump(
              tester,
              const MyBusinessScreen(),
              isProvider: true,
              bookings: _bookings,
              size: Size(width, 760),
              theme: theme.$2,
              locale: locale,
            );
            expect(find.text(titles[locale]!), findsOneWidget);
            expect(tester.takeException(), isNull);

            await tester.tap(find.byKey(const ValueKey('business-bookings')));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.pageBack();
            await tester.pumpAndSettle();

            await tester.tap(find.byKey(const ValueKey('business-statistics')));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          });

          testWidgets(
            'Home card ${theme.$1} · ${width.toInt()} · ${locale.name}',
            (tester) async {
              for (final provider in [false, true]) {
                await pump(
                  tester,
                  const HomeScreen(),
                  isProvider: provider,
                  bookings: _bookings,
                  size: Size(width, 760),
                  theme: theme.$2,
                  locale: locale,
                );
                await scrollTo(
                  tester,
                  find.byKey(const ValueKey('provider-card-cta')),
                );
                expect(tester.takeException(), isNull);
              }
            },
          );
        }
      }
    }
  });
}
