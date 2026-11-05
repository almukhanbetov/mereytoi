import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/models/user.dart';
import 'package:mereytoi_app/screens/home/home_screen.dart';
import 'package:mereytoi_app/screens/root_shell.dart';
import 'package:mereytoi_app/state/auth_provider.dart';
import 'package:mereytoi_app/state/locale_provider.dart';
import 'package:mereytoi_app/widgets/app_bottom_nav.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Storage extends FlutterSecureStoragePlatform {
  int deletes = 0;

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => false;
  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async => deletes++;
  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      deletes++;
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

const _button = ValueKey('home-exit-app');
const _stay = ValueKey('exit-app-stay');
const _confirm = ValueKey('exit-app-confirm');

class _Harness {
  _Harness(this.tester, this.storage, this.container, this.closes);

  final WidgetTester tester;
  final _Storage storage;
  final ProviderContainer container;
  final List<int> closes;

  bool get sheetOpen => find.byKey(_stay).evaluate().isNotEmpty;

  Future<void> systemBack() async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  Future<void> revealButton() async {
    await tester.scrollUntilVisible(
      find.byKey(_button),
      400,
      scrollable: find
          .descendant(
            of: find.byType(HomeScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(find.byKey(_button));
    await tester.pumpAndSettle();
  }
}

Future<_Harness> _pump(
  WidgetTester tester, {
  AppLocale locale = AppLocale.ru,
  ThemeData? theme,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final storage = _Storage();
  FlutterSecureStoragePlatform.instance = storage;
  SharedPreferences.setMockInitialValues({});

  final closes = <int>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'SystemNavigator.pop') closes.add(1);
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );

  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: theme ?? AppTheme.light,
        home: const RootShell(),
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
  return _Harness(tester, storage, container, closes);
}

void main() {
  testWidgets('system Back on Home asks; it does not close the app', (
    tester,
  ) async {
    final h = await _pump(tester);
    await h.systemBack();

    expect(find.text('Закрыть приложение?'), findsOneWidget);
    expect(find.text('Вы можете вернуться в любое время'), findsOneWidget);
    expect(h.closes, isEmpty);
  });

  testWidgets('«Остаться» only closes the sheet, even on a double tap', (
    tester,
  ) async {
    final h = await _pump(tester);
    await h.systemBack();
    await tester.tap(find.byKey(_stay));
    await tester.tap(find.byKey(_stay), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(h.sheetOpen, isFalse);
    expect(find.byType(RootShell), findsOneWidget);
    expect(h.closes, isEmpty);
  });

  testWidgets('Back and a tap outside also just close the sheet', (
    tester,
  ) async {
    final h = await _pump(tester);
    await h.systemBack();
    await h.systemBack();
    expect(h.sheetOpen, isFalse);
    expect(h.closes, isEmpty);

    await h.systemBack();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(h.sheetOpen, isFalse);
    expect(h.closes, isEmpty);
  });

  testWidgets(
    '«Выйти» closes the app once and keeps the session and the token',
    (tester) async {
      final h = await _pump(tester);
      await h.systemBack();
      final deletesBefore = h.storage.deletes;
      await tester.tap(find.byKey(_confirm));
      await tester.tap(find.byKey(_confirm), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(h.closes, hasLength(1));
      expect(h.container.read(authProvider), isA<AuthAuthenticated>());
      expect(h.storage.deletes, deletesBefore);
    },
  );

  testWidgets('the Home button asks, and a double tap opens one sheet', (
    tester,
  ) async {
    final h = await _pump(tester);
    await h.revealButton();
    expect(find.text('Выйти из приложения'), findsOneWidget);
    expect(find.byIcon(Icons.exit_to_app_rounded), findsOneWidget);

    // A real double tap: the second lands on the barrier, a frame or more later.
    final at = tester.getCenter(find.byKey(_button));
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tapAt(at);
    await tester.pumpAndSettle();
    expect(find.byKey(_stay), findsOneWidget);
    expect(h.closes, isEmpty);

    // Once open, a tap outside closes it as usual.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byKey(_stay), findsNothing);
    await h.revealButton();
    await tester.tap(find.byKey(_button));
    await tester.pumpAndSettle();
    expect(find.byKey(_stay), findsOneWidget);

    await tester.tap(find.byKey(_stay));
    await tester.pumpAndSettle();
    expect(find.byKey(_stay), findsNothing);
    await tester.tap(find.byKey(_button));
    await tester.pumpAndSettle();
    expect(find.byKey(_stay), findsOneWidget);
  });

  for (final (width, height) in [
    (320.0, 568.0),
    (390.0, 844.0),
    (430.0, 932.0),
  ]) {
    for (final locale in AppLocale.values) {
      testWidgets(
        '${locale.name} ${width.toInt()}x${height.toInt()}: exit button on the first screen',
        (tester) async {
          await _pump(tester, locale: locale, size: Size(width, height));
          // The bottom nav's labels wrap in the test font on narrow screens.
          tester.takeException();
          final button = find.byKey(_button);
          expect(button, findsOneWidget);
          final rect = tester.getRect(button);
          final navTop = tester.getTopLeft(find.byType(AppBottomNav)).dy;
          expect(rect.bottom, lessThanOrEqualTo(navTop));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(width));
          expect(rect.height, greaterThanOrEqualTo(48));
          expect(
            find.descendant(
              of: button,
              matching: find.byIcon(Icons.exit_to_app_rounded),
            ),
            findsOneWidget,
          );
        },
      );
    }
  }

  testWidgets('Back on another tab returns to Home, then asks', (tester) async {
    final h = await _pump(tester);
    h.container.read(selectedTabProvider.notifier).state = 2;
    await tester.pumpAndSettle();

    await h.systemBack();
    expect(h.container.read(selectedTabProvider), 0);
    expect(h.sheetOpen, isFalse);
    expect(h.closes, isEmpty);

    await h.systemBack();
    expect(h.sheetOpen, isTrue);
  });

  testWidgets(
    'Back on a nested screen goes back; it has a back button, Home has none',
    (tester) async {
      final h = await _pump(tester);
      expect(find.byType(BackButton), findsNothing);

      final context = tester.element(find.byType(RootShell));
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(appBar: AppBar(title: const Text('nested'))),
        ),
      );
      await tester.pumpAndSettle();

      final back = find.byType(BackButton);
      expect(back, findsOneWidget);
      expect(tester.getSize(back).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(back).height, greaterThanOrEqualTo(48));
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);

      await h.systemBack();
      expect(find.text('nested'), findsNothing);
      expect(h.sheetOpen, isFalse);
      expect(h.closes, isEmpty);
    },
  );

  testWidgets('a shell opened over another screen returns to it on Back', (
    tester,
  ) async {
    final h = await _pump(tester);
    final context = tester.element(find.byType(RootShell));
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const RootShell()));
    await tester.pumpAndSettle();
    expect(find.byType(RootShell, skipOffstage: false), findsNWidgets(2));
    expect(find.byType(BackButton), findsNothing);

    await h.systemBack();
    expect(find.byType(RootShell, skipOffstage: false), findsOneWidget);
    expect(h.sheetOpen, isFalse);
    expect(h.closes, isEmpty);
  });

  testWidgets('no exit button on iOS', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await _pump(tester);
    expect(find.byKey(_button, skipOffstage: false), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  const copy = {
    AppLocale.ru: [
      'Закрыть приложение?',
      'Вы можете вернуться в любое время',
      'Остаться',
      'Выйти',
      'Выйти из приложения',
    ],
    AppLocale.kz: [
      'Қолданбаны жабу керек пе?',
      'Кез келген уақытта орала аласыз',
      'Қалу',
      'Шығу',
      'Қолданбадан шығу',
    ],
    AppLocale.en: [
      'Close the app?',
      'You can come back at any time',
      'Stay',
      'Exit',
      'Exit the app',
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
            // The bottom nav's labels wrap in the test font on narrow screens;
            // only what the button and the sheet add is checked here.
            tester.takeException();
            await h.revealButton();
            expect(find.text(strings[4]), findsOneWidget);
            expect(
              tester.getSize(find.byKey(_button)).height,
              greaterThanOrEqualTo(48),
            );

            await tester.tap(find.byKey(_button));
            await tester.pumpAndSettle();
            for (final text in strings.take(4)) {
              expect(
                find.descendant(
                  of: find.byType(BottomSheet),
                  matching: find.text(text),
                ),
                findsOneWidget,
              );
            }
            for (final key in [_stay, _confirm]) {
              expect(
                tester.getSize(find.byKey(key)).height,
                greaterThanOrEqualTo(48),
              );
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
