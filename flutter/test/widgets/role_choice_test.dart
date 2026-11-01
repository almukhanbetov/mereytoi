import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/app.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/models/category.dart';
import 'package:mereytoi_app/models/event.dart';
import 'package:mereytoi_app/models/site_statistics.dart';
import 'package:mereytoi_app/models/user.dart';
import 'package:mereytoi_app/screens/auth/login_screen.dart';
import 'package:mereytoi_app/screens/profile/profile_screen.dart';
import 'package:mereytoi_app/screens/provider/business/my_business_screen.dart';
import 'package:mereytoi_app/screens/provider/onboarding/provider_onboarding_screen.dart';
import 'package:mereytoi_app/screens/provider/onboarding/provider_onboarding_success_screen.dart';
import 'package:mereytoi_app/screens/role_choice/role_choice_screen.dart';
import 'package:mereytoi_app/screens/root_shell.dart';
import 'package:mereytoi_app/screens/splash/splash_screen.dart';
import 'package:mereytoi_app/state/app_mode_provider.dart';
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

User _user(int id) => User(
  id: id,
  name: 'Алия',
  email: 'aliya$id@example.com',
  phone: '+7 700 000 00 00',
  role: 'user',
  status: 'active',
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

const _categories = [
  Category(
    id: 2,
    slug: 'hosts',
    nameRu: 'Ведущие',
    nameKz: 'Жүргізушілер',
    position: 1,
  ),
];

final _provider = <String, dynamic>{
  'id': 5,
  'user_id': 9,
  'display_name': 'Dana Events',
  'city': 'Алматы',
  'experience_years': 7,
  'status': 'active',
};

void main() {
  setUp(() {
    FlutterSecureStoragePlatform.instance = _EmptySecureStoragePlatform();
  });

  /// Pumps [home] (default: the role choice) with the provider fake API.
  /// [storedMode] seeds the remembered mode; [signedIn] signs in once the
  /// (empty) stored session has been restored.
  Future<(ProviderContainer, ProviderFakeApi)> pump(
    WidgetTester tester, {
    Widget home = const RoleChoiceScreen(),
    bool signedIn = false,
    bool isProvider = false,
    String? storedMode,
    Size size = const Size(390, 844),
    ThemeData Function()? theme,
    AppLocale locale = AppLocale.ru,
    double textScale = 1,
    bool settle = true,
  }) async {
    SharedPreferences.setMockInitialValues({
      if (locale != AppLocale.ru) 'app_locale_v1': locale.name,
      'app_mode_v1': ?storedMode,
    });
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final (client, api) = fakeProviderApi(
      existingProvider: isProvider ? Map.of(_provider) : null,
    );
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        categoriesProvider.overrideWith((ref) => Future.value(_categories)),
        listingsProvider(null).overrideWith((ref) => Future.value(const [])),
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
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: home,
        ),
      ),
    );
    await tester.pump();
    while (container.read(authProvider) is AuthLoading ||
        container.read(authProvider) is AuthInitial) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    if (signedIn) {
      container.read(authProvider.notifier).state = AuthAuthenticated(_user(9));
    }
    if (settle) await tester.pumpAndSettle();
    return (container, api);
  }

  Future<void> tapCard(WidgetTester tester, String key) async {
    final card = find.byKey(ValueKey(key));
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    await tester.tap(card);
    await tester.pumpAndSettle();
  }

  group('role choice', () {
    testWidgets('title, subtitle and the two modes', (tester) async {
      await pump(tester);
      expect(find.text('Один аккаунт — два режима'), findsOneWidget);
      expect(
        find.text(
          'Выберите, что вы хотите делать сейчас. '
          'Переключиться можно в любой момент.',
        ),
        findsOneWidget,
      );
      Finder inCard(String key, String text) => find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.text(text),
      );
      expect(inCard('role-client', 'Для мероприятия'), findsOneWidget);
      expect(inCard('role-client', 'Ищу услуги'), findsOneWidget);
      expect(inCard('role-business', 'Для бизнеса'), findsOneWidget);
      expect(inCard('role-business', 'Предлагаю услуги'), findsOneWidget);
      // Never the heavy legal terms as the main titles.
      expect(find.textContaining('Услугополучатель'), findsNothing);
      expect(find.textContaining('Услугодатель'), findsNothing);
    });

    testWidgets('same size; the tapped card shows as selected', (tester) async {
      await pump(tester, size: const Size(390, 1200));
      final client = find.byKey(const ValueKey('role-client'));
      final business = find.byKey(const ValueKey('role-business'));
      expect(tester.getSize(client), tester.getSize(business));

      bool selected(Finder card) =>
          tester
              .widget<Semantics>(
                find
                    .descendant(of: card, matching: find.byType(Semantics))
                    .first,
              )
              .properties
              .selected ==
          true;
      double check(Finder card) => tester
          .widget<AnimatedOpacity>(
            find
                .ancestor(
                  of: find.descendant(
                    of: card,
                    matching: find.byKey(const ValueKey('mode-selected-check')),
                  ),
                  matching: find.byType(AnimatedOpacity),
                )
                .first,
          )
          .opacity;
      expect(selected(client), isFalse);
      expect(check(client), 0);

      await tester.tap(client);
      await tester.pump(const Duration(milliseconds: 100));
      expect(selected(client), isTrue);
      expect(check(client), 1);
      expect(selected(business), isFalse);
      await tester.pumpAndSettle();
    });

    testWidgets('for an event → the client app, remembered', (tester) async {
      final (container, _) = await pump(tester);
      await tapCard(tester, 'role-client');
      expect(find.byType(RootShell), findsOneWidget);
      expect(find.byType(RoleChoiceScreen), findsNothing);
      expect(container.read(appModeProvider), AppMode.client);
      await container.read(appModeProvider.notifier).debugPersisted;
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_mode_v1'), 'client');
    });

    testWidgets('business, not a provider → the onboarding over the app', (
      tester,
    ) async {
      final (container, _) = await pump(tester, signedIn: true);
      await tapCard(tester, 'role-business');
      expect(
        tester
            .widget<ProviderOnboardingScreen>(
              find.byType(ProviderOnboardingScreen),
            )
            .openBusinessWhenDone,
        isTrue,
      );
      expect(container.read(appModeProvider), AppMode.business);
      // Back from the business side lands in the client app.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(RootShell), findsOneWidget);
    });

    testWidgets('business, already a provider → «Мой бизнес»', (tester) async {
      await pump(tester, signedIn: true, isProvider: true);
      await tapCard(tester, 'role-business');
      expect(find.byType(MyBusinessScreen), findsOneWidget);
      expect(find.text('Dana Events'), findsOneWidget);
    });

    for (final isProvider in [false, true]) {
      testWidgets('guest, business → sign in → '
          '${isProvider ? '«Мой бизнес»' : 'onboarding'}, no second choice', (
        tester,
      ) async {
        final (container, api) = await pump(tester, isProvider: isProvider);
        await tapCard(tester, 'role-business');
        expect(find.byType(LoginScreen), findsOneWidget);

        // What a successful sign-in does; the login screen closes itself.
        container.read(authProvider.notifier).state = AuthAuthenticated(
          _user(9),
        );
        await tester.pumpAndSettle();
        expect(find.byType(LoginScreen), findsNothing);
        expect(find.byType(RoleChoiceScreen), findsNothing);
        expect(
          find.byType(isProvider ? MyBusinessScreen : ProviderOnboardingScreen),
          findsOneWidget,
        );
        // Choosing a mode never creates anything on the backend.
        expect(api.count('POST /api/provider'), 0);
      });
    }

    testWidgets('guest backing out of sign-in stays on the choice', (
      tester,
    ) async {
      await pump(tester);
      await tapCard(tester, 'role-business');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(RoleChoiceScreen), findsOneWidget);
    });
  });

  group('launch', () {
    Future<void> launch(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();
    }

    testWidgets('first launch asks for the mode', (tester) async {
      await pump(tester, home: const SplashScreen(), settle: false);
      await launch(tester);
      expect(find.byType(RoleChoiceScreen), findsOneWidget);
    });

    testWidgets('later launches open the last mode: client', (tester) async {
      await pump(
        tester,
        home: const SplashScreen(),
        storedMode: 'client',
        settle: false,
      );
      await launch(tester);
      expect(find.byType(RootShell), findsOneWidget);
      expect(find.byType(RoleChoiceScreen), findsNothing);
      expect(find.byType(MyBusinessScreen), findsNothing);
    });

    testWidgets('business + provider → «Мой бизнес» over the app', (
      tester,
    ) async {
      await pump(
        tester,
        home: const SplashScreen(),
        storedMode: 'business',
        signedIn: true,
        isProvider: true,
        settle: false,
      );
      await launch(tester);
      expect(find.byType(MyBusinessScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(RootShell), findsOneWidget);
    });

    testWidgets('business, signed out → the client app, mode reset', (
      tester,
    ) async {
      final (container, _) = await pump(
        tester,
        home: const SplashScreen(),
        storedMode: 'business',
        settle: false,
      );
      await launch(tester);
      expect(find.byType(RootShell), findsOneWidget);
      expect(find.byType(ProviderOnboardingScreen), findsNothing);
      expect(container.read(appModeProvider), AppMode.client);
    });
  });

  group('Profile mode switch', () {
    testWidgets('non-provider: business → onboarding', (tester) async {
      final (container, _) = await pump(
        tester,
        home: const ProfileScreen(),
        signedIn: true,
      );
      expect(find.text('Режим приложения'), findsOneWidget);
      expect(find.text('Текущий режим: Для мероприятия'), findsOneWidget);
      expect(find.text('Предлагаю услуги'), findsOneWidget);
      expect(find.text('Стать услугодателем'), findsOneWidget);
      await tapCard(tester, 'profile-become-provider');
      expect(find.byType(ProviderOnboardingScreen), findsOneWidget);
      expect(container.read(appModeProvider), AppMode.business);
    });

    testWidgets('provider: business → «Мой бизнес»; event → back to client', (
      tester,
    ) async {
      final (container, api) = await pump(
        tester,
        home: const ProfileScreen(),
        signedIn: true,
        isProvider: true,
      );
      expect(find.text('Текущий режим: Для мероприятия'), findsOneWidget);
      expect(find.text('Мой бизнес'), findsOneWidget);
      expect(find.text('Открыть'), findsOneWidget);
      await tapCard(tester, 'profile-my-business');
      expect(find.byType(MyBusinessScreen), findsOneWidget);
      expect(container.read(appModeProvider), AppMode.business);

      // Back in Profile, it says so.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Текущий режим: Мой бизнес'), findsOneWidget);
      await tapCard(tester, 'profile-mode-client');
      expect(container.read(appModeProvider), AppMode.client);
      expect(container.read(selectedTabProvider), 0);

      // And business again: the same provider, no re-login, nothing new.
      await tapCard(tester, 'profile-my-business');
      expect(find.byType(MyBusinessScreen), findsOneWidget);
      expect(container.read(authProvider), isA<AuthAuthenticated>());
      expect(api.count('POST /api/provider'), 0);
    });
  });

  testWidgets('business success screen leads to «Мой бизнес»', (tester) async {
    await pump(
      tester,
      home: const ProviderOnboardingSuccessScreen(openBusiness: true),
      signedIn: true,
      isProvider: true,
    );
    expect(find.byKey(const ValueKey('success-my-services')), findsNothing);
    await tapCard(tester, 'success-my-business');
    expect(find.byType(MyBusinessScreen), findsOneWidget);
  });

  testWidgets('signing out resets the mode; another account starts clean', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'app_mode_v1': 'business'});
    final (client, api) = fakeProviderApi(existingProvider: Map.of(_provider));
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MereytoiApp(),
      ),
    );
    // Dio and the stored-mode read complete on timers, which only run
    // while the test pumps.
    Future<AsyncValue<T>> settled<T>(
      ProviderListenable<AsyncValue<T>> p,
    ) async {
      for (var i = 0; i < 200 && container.read(p).isLoading; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      return container.read(p);
    }

    for (var i = 0; i < 50 && container.read(appModeProvider) == null; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(container.read(appModeProvider), AppMode.business);
    container.read(authProvider.notifier).state = AuthAuthenticated(_user(9));
    await tester.pump();
    final sub = container.listen(providerProfileProvider, (_, _) {});
    addTearDown(sub.close);
    expect((await settled(providerProfileProvider)).valueOrNull, isNotNull);
    // The first account's own services, as «Мой бизнес» counts them.
    api.listings.add({
      'id': 101,
      'category_id': 2,
      'name_ru': 'Проведение тоя',
      'name_kz': 'Той жүргізу',
      'price': 150000,
      'city': 'Алматы',
      'rating': 0,
      'is_active': true,
    });
    final listingsSub = container.listen(myListingsProvider, (_, _) {});
    addTearDown(listingsSub.close);
    expect((await settled(myListingsProvider)).valueOrNull, hasLength(1));

    container.read(authProvider.notifier).state = const AuthUnauthenticated();
    await tester.pump();
    expect(container.read(appModeProvider), AppMode.client);

    // Another account on the same device: no provider of its own, and the
    // previous one's profile and services are gone from the cache.
    api.provider = null;
    api.listings.clear();
    container.read(authProvider.notifier).state = AuthAuthenticated(_user(10));
    await tester.pump();
    expect((await settled(providerProfileProvider)).valueOrNull, isNull);
    expect((await settled(myListingsProvider)).valueOrNull, isEmpty);

    // Let the splash finish so no timers outlive the test.
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 600));
  });

  group('no overflow', () {
    final themes = <(String, ThemeData Function())>[
      ('light', () => AppTheme.light),
      ('dark', () => AppTheme.dark),
    ];
    for (final theme in themes) {
      for (final width in [320.0, 390.0, 430.0]) {
        for (final locale in AppLocale.values) {
          for (final scale in [1.0, 1.3]) {
            final label =
                '${theme.$1} · ${width.toInt()} · ${locale.name} · ×$scale';
            testWidgets('role choice · $label', (tester) async {
              await pump(
                tester,
                size: Size(width, 760),
                theme: theme.$2,
                locale: locale,
                textScale: scale,
              );
              // Both cards, scrolled fully into view.
              await tester.scrollUntilVisible(
                find.byKey(const ValueKey('role-business')),
                200,
                scrollable: find.byType(Scrollable).first,
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
            });

            testWidgets('profile mode · $label', (tester) async {
              await pump(
                tester,
                home: const ProfileScreen(),
                signedIn: true,
                isProvider: true,
                size: Size(width, 760),
                theme: theme.$2,
                locale: locale,
                textScale: scale,
              );
              await tester.scrollUntilVisible(
                find.byKey(const ValueKey('profile-my-business')),
                200,
                scrollable: find.byType(Scrollable).first,
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
            });
          }
        }
      }
    }
  });
}
