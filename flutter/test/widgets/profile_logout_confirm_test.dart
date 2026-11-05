import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/models/event.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/models/user.dart';
import 'package:mereytoi_app/screens/profile/profile_screen.dart';
import 'package:mereytoi_app/state/auth_provider.dart';
import 'package:mereytoi_app/state/event_providers.dart';
import 'package:mereytoi_app/state/listings_provider.dart';
import 'package:mereytoi_app/state/locale_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Counts what logout really does to secure storage. Holds the delete open
/// when [hold] is set, so a test can look at the sheet mid sign-out.
class _Storage extends FlutterSecureStoragePlatform {
  final deletedKeys = <String>[];
  int deleteAllCalls = 0;
  Completer<void>? hold;

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => false;
  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    deletedKeys.add(key);
    await hold?.future;
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    deleteAllCalls++;
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async => null;
  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => const {};
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

const _homeKey = ValueKey('test-home');
const _exit = ValueKey('profile-logout');
const _stay = ValueKey('logout-stay');
const _confirm = ValueKey('logout-confirm');

class _Harness {
  _Harness(this.tester, this.storage, this.container);

  final WidgetTester tester;
  final _Storage storage;
  final ProviderContainer container;

  bool get signedIn => container.read(authProvider) is AuthAuthenticated;
  bool get onProfile => find.byType(ProfileScreen).evaluate().isNotEmpty;
  bool get sheetOpen => find.byKey(_stay).evaluate().isNotEmpty;

  /// Scrolls the lazy profile list to «Выйти» and taps it once.
  Future<void> openSheet() async {
    await revealExit();
    await tester.tap(find.byKey(_exit));
    await tester.pumpAndSettle();
  }

  Future<void> revealExit() async {
    await tester.scrollUntilVisible(
      find.byKey(_exit),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    // Lazily built can still mean just past the screen edge.
    await tester.ensureVisible(find.byKey(_exit));
    await tester.pumpAndSettle();
  }

  void expectStillSignedInOnProfile() {
    expect(signedIn, isTrue);
    expect(storage.deletedKeys, isEmpty);
    expect(onProfile, isTrue);
    expect(sheetOpen, isFalse);
  }
}

/// A real route stack: home → pushed profile, as in the app.
Future<_Harness> _pump(
  WidgetTester tester, {
  AppLocale locale = AppLocale.ru,
  ThemeData? theme,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  final storage = _Storage();
  FlutterSecureStoragePlatform.instance = storage;
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      eventsProvider.overrideWith((ref) => Future.value(const <Event>[])),
      myListingsProvider.overrideWith((ref) => Future.value(const <Listing>[])),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: theme ?? AppTheme.dark,
        home: Builder(
          builder: (context) => Scaffold(
            key: _homeKey,
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ProfileScreen(),
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
  while (container.read(authProvider) is AuthLoading ||
      container.read(authProvider) is AuthInitial) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  await container.read(localeProvider.notifier).ready;
  container.read(localeProvider.notifier).setLocale(locale);
  container.read(authProvider.notifier).state = AuthAuthenticated(_user);
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return _Harness(tester, storage, container);
}

void main() {
  testWidgets('«Выйти» only asks: no logout yet', (tester) async {
    final h = await _pump(tester);
    await h.openSheet();

    expect(find.text('Выйти из аккаунта?'), findsOneWidget);
    expect(find.text('Вы уверены, что хотите выйти?'), findsOneWidget);
    expect(h.signedIn, isTrue);
    expect(h.storage.deletedKeys, isEmpty);
  });

  testWidgets('«Остаться» closes the sheet and changes nothing', (
    tester,
  ) async {
    final h = await _pump(tester);
    await h.openSheet();
    await tester.tap(find.byKey(_stay));
    await tester.pumpAndSettle();
    h.expectStillSignedInOnProfile();
  });

  testWidgets('a double tap on «Остаться» does not pop the profile', (
    tester,
  ) async {
    final h = await _pump(tester);
    await h.openSheet();
    await tester.tap(find.byKey(_stay));
    await tester.tap(find.byKey(_stay), warnIfMissed: false);
    await tester.pumpAndSettle();
    h.expectStillSignedInOnProfile();
  });

  testWidgets('system Back acts like «Остаться»', (tester) async {
    final h = await _pump(tester);
    await h.openSheet();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    h.expectStillSignedInOnProfile();
  });

  testWidgets('a tap outside acts like «Остаться»', (tester) async {
    final h = await _pump(tester);
    await h.openSheet();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    h.expectStillSignedInOnProfile();
  });

  testWidgets('a swipe down does not close or sign out', (tester) async {
    final h = await _pump(tester);
    await h.openSheet();
    await tester.drag(find.text('Выйти из аккаунта?'), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(h.sheetOpen, isTrue);
    expect(h.signedIn, isTrue);
  });

  testWidgets('a double tap on the profile button opens one sheet', (
    tester,
  ) async {
    final h = await _pump(tester);
    await h.revealExit();
    await tester.tap(find.byKey(_exit));
    await tester.tap(find.byKey(_exit));
    await tester.pumpAndSettle();
    expect(find.byKey(_stay), findsOneWidget);

    await tester.tap(find.byKey(_stay));
    await tester.pumpAndSettle();
    expect(find.byKey(_stay), findsNothing);
    expect(h.onProfile, isTrue);
  });

  testWidgets('the profile button works again after «Остаться»', (
    tester,
  ) async {
    final h = await _pump(tester);
    await h.openSheet();
    await tester.tap(find.byKey(_stay));
    await tester.pumpAndSettle();
    await h.openSheet();
    expect(h.sheetOpen, isTrue);
  });

  testWidgets(
    'confirming signs out once, clears only the token, returns home',
    (tester) async {
      final h = await _pump(tester);
      await h.openSheet();
      await tester.tap(find.byKey(_confirm));
      await tester.pumpAndSettle();

      expect(h.container.read(authProvider), isA<AuthUnauthenticated>());
      expect(h.storage.deletedKeys, hasLength(1));
      expect(h.storage.deleteAllCalls, 0);
      expect(h.onProfile, isFalse);
      expect(h.sheetOpen, isFalse);
      expect(find.byKey(_homeKey), findsOneWidget);
    },
  );

  testWidgets(
    'during sign-out: one logout on a double tap, nothing can dismiss the sheet',
    (tester) async {
      final h = await _pump(tester);
      await h.openSheet();
      final hold = h.storage.hold = Completer<void>();

      await tester.tap(find.byKey(_confirm));
      await tester.tap(find.byKey(_confirm), warnIfMissed: false);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester.widget<ElevatedButton>(find.byKey(_stay)).onPressed,
        isNull,
      );
      expect(
        tester.widget<OutlinedButton>(find.byKey(_confirm)).onPressed,
        isNull,
      );

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tapAt(const Offset(10, 10));
      await tester.pump(const Duration(milliseconds: 400));
      expect(h.sheetOpen, isTrue);
      expect(h.onProfile, isTrue);
      expect(h.signedIn, isTrue);

      hold.complete();
      await tester.pumpAndSettle();

      expect(h.storage.deletedKeys, hasLength(1));
      expect(h.container.read(authProvider), isA<AuthUnauthenticated>());
      expect(h.sheetOpen, isFalse);
      expect(find.byKey(_homeKey), findsOneWidget);
    },
  );

  const copy = {
    AppLocale.ru: [
      'Выйти из аккаунта?',
      'Вы уверены, что хотите выйти?',
      'Остаться',
      'Выйти',
    ],
    AppLocale.kz: [
      'Аккаунттан шығу керек пе?',
      'Аккаунттан шығуға сенімдісіз бе?',
      'Қалу',
      'Шығу',
    ],
    AppLocale.en: [
      'Sign out?',
      'Are you sure you want to sign out?',
      'Stay',
      'Sign out',
    ],
  };

  for (final MapEntry(key: locale, value: strings) in copy.entries) {
    for (final themeName in ['light', 'dark']) {
      for (final width in [320.0, 390.0, 430.0]) {
        testWidgets(
          '${locale.name} $themeName ${width.toInt()}dp: copy, no overflow, 48dp',
          (tester) async {
            final h = await _pump(
              tester,
              locale: locale,
              theme: themeName == 'light' ? AppTheme.light : AppTheme.dark,
              size: Size(width, 700),
            );
            await h.openSheet();

            final sheet = find.ancestor(
              of: find.byKey(_stay),
              matching: find.byType(BottomSheet),
            );
            for (final text in strings) {
              expect(
                find.descendant(of: sheet, matching: find.text(text)),
                findsOneWidget,
              );
            }
            for (final key in [_stay, _confirm]) {
              final size = tester.getSize(find.byKey(key));
              expect(size.height, greaterThanOrEqualTo(48));
              expect(size.width, greaterThanOrEqualTo(48));
            }
            // A layout overflow reports itself as an exception.
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  for (final locale in AppLocale.values) {
    testWidgets('${locale.name}: large text on a short 320dp screen fits', (
      tester,
    ) async {
      final h = await _pump(
        tester,
        locale: locale,
        size: const Size(320, 480),
        textScale: 2,
      );
      await h.revealExit();
      // The profile behind the sheet has its own overflow at this text size;
      // only what opening the sheet adds is checked here.
      tester.takeException();
      await h.openSheet();
      expect(tester.takeException(), isNull);
      // Reachable by scrolling, so it can still be pressed.
      await tester.ensureVisible(find.byKey(_confirm));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_confirm));
      await tester.pumpAndSettle();
      expect(h.container.read(authProvider), isA<AuthUnauthenticated>());
    });
  }
}
