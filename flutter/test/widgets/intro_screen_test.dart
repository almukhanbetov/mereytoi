import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/screens/intro/intro_screen.dart';
import 'package:mereytoi_app/screens/role_choice/role_choice_screen.dart';
import 'package:mereytoi_app/state/locale_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

void main() {
  setUp(() {
    FlutterSecureStoragePlatform.instance = _EmptySecureStoragePlatform();
  });

  Future<void> pumpIntro(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    ThemeData Function()? theme,
    AppLocale locale = AppLocale.ru,
    double textScale = 1,
  }) async {
    SharedPreferences.setMockInitialValues({
      if (locale != AppLocale.ru) 'app_locale_v1': locale.name,
    });
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: (theme ?? () => AppTheme.light)(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const IntroScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder next() => find.byKey(const ValueKey('intro-next'));

  double dotWidth(WidgetTester tester, int i) =>
      tester.getSize(find.byKey(ValueKey('intro-dot-$i'))).width;

  testWidgets('three pages: «Далее», «Далее», «Начать» → the mode choice', (
    tester,
  ) async {
    await pumpIntro(tester);
    expect(
      find.text('Всё для вашего мероприятия — в одном приложении'),
      findsOneWidget,
    );
    expect(find.text('Далее'), findsOneWidget);
    expect(dotWidth(tester, 0), greaterThan(dotWidth(tester, 1)));

    await tester.tap(next());
    await tester.pumpAndSettle();
    expect(find.text('Один аккаунт — два режима'), findsOneWidget);
    expect(find.text('Для мероприятия'), findsOneWidget);
    expect(find.text('Для бизнеса'), findsOneWidget);
    expect(dotWidth(tester, 1), greaterThan(dotWidth(tester, 0)));

    await tester.tap(next());
    await tester.pumpAndSettle();
    expect(find.text('Создавайте события проще'), findsOneWidget);
    expect(
      find.textContaining('Переключаться между режимами можно в любой момент.'),
      findsOneWidget,
    );
    expect(find.text('Начать'), findsOneWidget);

    await tester.tap(next());
    await tester.pumpAndSettle();
    expect(find.byType(RoleChoiceScreen), findsOneWidget);
    expect(find.byType(IntroScreen), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('intro_seen_v1'), isTrue);
  });

  testWidgets('a quick double tap never skips the last page', (tester) async {
    await pumpIntro(tester);
    await tester.tap(next());
    await tester.pumpAndSettle();
    // Second page: tap twice while it turns.
    await tester.tap(next());
    // Mid-turn: the index (and the button label) has already switched.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(find.text('Начать'), findsOneWidget);
    await tester.tap(next());
    await tester.pumpAndSettle();
    expect(find.text('Создавайте события проще'), findsOneWidget);
    expect(find.byType(RoleChoiceScreen), findsNothing);
  });

  testWidgets('pages can be swiped too', (tester) async {
    await pumpIntro(tester);
    await tester.drag(
      find.byKey(const ValueKey('intro-pages')),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('Один аккаунт — два режима'), findsOneWidget);
  });

  testWidgets('language can be switched right on the intro', (tester) async {
    await pumpIntro(tester);
    await tester.tap(find.byKey(const ValueKey('intro-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Қазақша'));
    await tester.pumpAndSettle();
    expect(
      find.text('Іс-шараңызға қажеттінің бәрі — бір қосымшада'),
      findsOneWidget,
    );
    expect(find.text('Әрі қарай'), findsOneWidget);
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
            testWidgets(
              '${theme.$1} · ${width.toInt()} · ${locale.name} · ×$scale',
              (tester) async {
                await pumpIntro(
                  tester,
                  size: Size(width, 700),
                  theme: theme.$2,
                  locale: locale,
                  textScale: scale,
                );
                for (var page = 0; page < 3; page++) {
                  expect(tester.takeException(), isNull);
                  if (page < 2) {
                    await tester.tap(next());
                    await tester.pumpAndSettle();
                  }
                }
                expect(tester.takeException(), isNull);
              },
            );
          }
        }
      }
    }
  });
}
