import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/network/api_client.dart';
import 'package:mereytoi_app/core/network/api_exception.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/domain/auth/password_reset_rules.dart';
import 'package:mereytoi_app/screens/auth/login_screen.dart';
import 'package:mereytoi_app/services/auth_service.dart';
import 'package:mereytoi_app/state/locale_provider.dart';
import 'package:mereytoi_app/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stands in for the backend's three password-reset endpoints.
class _FakeAuth extends AuthService {
  _FakeAuth() : super(ApiClient.test(tokenProvider: () async => null));

  bool available = true;
  Object? configError;

  final forgotCalls = <Map<String, String>>[];
  Completer<void>? forgotGate;
  Object? forgotError;

  final resetCalls = <Map<String, String>>[];
  Object? resetError;

  @override
  Future<bool> fetchPasswordResetConfig() async {
    if (configError != null) throw configError!;
    return available;
  }

  @override
  Future<int> requestPasswordReset({
    required String phone,
    required String lang,
  }) async {
    forgotCalls.add({'phone': phone, 'lang': lang});
    if (forgotGate != null) await forgotGate!.future;
    if (forgotError != null) throw forgotError!;
    return 60;
  }

  @override
  Future<void> resetPassword({
    required String phone,
    required String code,
    required String newPassword,
  }) async {
    resetCalls.add({'phone': phone, 'code': code, 'new_password': newPassword});
    if (resetError != null) throw resetError!;
  }
}

const _invalidCode = ApiException(
  ApiErrorType.unknown,
  statusCode: 400,
  debugMessage: 'invalid_code',
);

Finder _key(String k) => find.byKey(ValueKey(k));

Future<_FakeAuth> _pumpLogin(
  WidgetTester tester, {
  _FakeAuth? auth,
  AppLocale locale = AppLocale.ru,
  ThemeData? theme,
  Size size = const Size(390, 844),
  double keyboard = 0,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);

  final fake = auth ?? _FakeAuth();
  final container = ProviderContainer(
    overrides: [authServiceProvider.overrideWithValue(fake)],
  );
  addTearDown(container.dispose);
  container.read(localeProvider.notifier).setLocale(locale);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: theme ?? AppTheme.dark,
        home: const LoginScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return fake;
}

/// Login → "Forgot password?" → the phone step.
Future<void> _openForgot(WidgetTester tester) async {
  await tester.ensureVisible(_key('forgot-password-link'));
  await tester.tap(_key('forgot-password-link'));
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, String key) async {
  await tester.ensureVisible(_key(key));
  await tester.pump();
  await tester.tap(_key(key));
  await tester.pump();
}

/// Phone → code step with a valid number.
Future<void> _toCodeStep(WidgetTester tester) async {
  await _openForgot(tester);
  await tester.enterText(_key('reset-phone'), '8 701 123 45 45');
  await _tapVisible(tester, 'reset-get-code');
  await tester.pump();
}

/// Code → password step with 123456.
Future<void> _toPasswordStep(WidgetTester tester) async {
  await _toCodeStep(tester);
  await tester.enterText(_key('otp-input'), '123456');
  await tester.pump();
  await _tapVisible(tester, 'reset-code-continue');
}

Future<void> _systemBack(WidgetTester tester) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
    (_) {},
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Login link', () {
    testWidgets('1. reset_available=false → no link', (tester) async {
      await _pumpLogin(tester, auth: _FakeAuth()..available = false);
      expect(_key('forgot-password-link'), findsNothing);
      expect(find.text('Забыли пароль?'), findsNothing);
    });

    testWidgets('2. reset_available=true → secondary text link', (
      tester,
    ) async {
      await _pumpLogin(tester);
      expect(find.text('Забыли пароль?'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('Забыли пароль?'),
          matching: find.byType(TextButton),
        ),
        findsOneWidget,
      );
    });

    testWidgets('3. config error → link hidden, login still works', (
      tester,
    ) async {
      await _pumpLogin(
        tester,
        auth: _FakeAuth()
          ..configError = const ApiException(ApiErrorType.network),
      );
      expect(_key('forgot-password-link'), findsNothing);
      expect(find.text('Войти'), findsWidgets);
      await tester.enterText(find.byType(TextFormField).first, 'a@b.kz');
      expect(tester.takeException(), isNull);
    });
  });

  group('Phone step', () {
    testWidgets('4. phone validation; a valid number is sent normalized', (
      tester,
    ) async {
      final auth = await _pumpLogin(tester);
      await _openForgot(tester);
      expect(find.text('Восстановление пароля'), findsOneWidget);
      expect(find.text('Получить код'), findsOneWidget);

      await tester.enterText(_key('reset-phone'), '123');
      await _tapVisible(tester, 'reset-get-code');
      expect(
        find.text('Введите номер в формате +7 7XX XXX XX XX'),
        findsOneWidget,
      );
      expect(auth.forgotCalls, isEmpty);

      await tester.enterText(_key('reset-phone'), '8 (701) 123-45-45');
      await _tapVisible(tester, 'reset-get-code');
      await tester.pump();
      expect(auth.forgotCalls, [
        {'phone': '+77011234545', 'lang': 'ru'},
      ]);
    });

    testWidgets('5. neutral response → code step, masked number, '
        'WhatsApp note, no "not found"', (tester) async {
      await _pumpLogin(tester);
      await _toCodeStep(tester);
      expect(_key('step-code'), findsOneWidget);
      expect(find.text('+7 701 ••• •• 45'), findsOneWidget);
      expect(find.textContaining('11234545'), findsNothing);
      expect(
        find.text('Если номер зарегистрирован, код придёт в WhatsApp.'),
        findsOneWidget,
      );
      expect(find.textContaining('не найден'), findsNothing);
    });

    testWidgets('too many requests → message, stays on phone step', (
      tester,
    ) async {
      await _pumpLogin(
        tester,
        auth: _FakeAuth()
          ..forgotError = const ApiException(
            ApiErrorType.unknown,
            statusCode: 429,
            debugMessage: 'too_many_requests',
          ),
      );
      await _toCodeStep(tester);
      expect(_key('step-phone'), findsOneWidget);
      expect(
        find.text('Слишком много попыток. Попробуйте позже.'),
        findsOneWidget,
      );
    });
  });

  group('Code step', () {
    testWidgets('6. OTP takes 6 digits only (typing and paste)', (
      tester,
    ) async {
      await _pumpLogin(tester);
      await _toCodeStep(tester);
      final next = _key('reset-code-continue');
      expect(tester.widget<ElevatedButton>(next).onPressed, isNull);

      await tester.enterText(_key('otp-input'), '12a3456789');
      await tester.pump();
      expect(
        tester.widget<TextField>(_key('otp-input')).controller!.text,
        '123456',
      );
      expect(tester.widget<ElevatedButton>(next).onPressed, isNotNull);

      await tester.enterText(_key('otp-input'), 'Код: 654 321');
      await tester.pump();
      expect(
        tester.widget<TextField>(_key('otp-input')).controller!.text,
        '654321',
      );

      await tester.enterText(_key('otp-input'), '65432'); // backspace
      await tester.pump();
      expect(tester.widget<ElevatedButton>(next).onPressed, isNull);
    });

    testWidgets('7. resend countdown 01:00 → 00:00 → resend button', (
      tester,
    ) async {
      await _pumpLogin(tester);
      await _toCodeStep(tester);
      expect(find.text('Повторно отправить через 01:00'), findsOneWidget);
      expect(_key('reset-resend'), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Повторно отправить через 00:59'), findsOneWidget);
      await tester.pump(const Duration(seconds: 59));
      expect(_key('reset-countdown'), findsNothing);
      expect(find.text('Отправить код снова'), findsOneWidget);
    });

    testWidgets('8. resend: loading, double tap blocked, countdown restarts', (
      tester,
    ) async {
      final auth = await _pumpLogin(tester);
      await _toCodeStep(tester);
      await tester.pump(const Duration(seconds: 60));
      auth.forgotGate = Completer<void>();

      await _tapVisible(tester, 'reset-resend');
      await tester.tap(_key('reset-resend'), warnIfMissed: false);
      await tester.pump();
      expect(auth.forgotCalls, hasLength(2)); // initial + one resend
      expect(tester.widget<TextButton>(_key('reset-resend')).onPressed, isNull);

      auth.forgotGate!.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('Повторно отправить через 01:00'), findsOneWidget);
      expect(auth.forgotCalls, hasLength(2));
    });
  });

  group('Password step', () {
    testWidgets('9. fewer than 8 characters is refused', (tester) async {
      final auth = await _pumpLogin(tester);
      await _toPasswordStep(tester);
      await tester.enterText(_key('reset-new-password'), 'short');
      await tester.enterText(_key('reset-repeat-password'), 'short');
      await _tapVisible(tester, 'reset-submit');
      expect(find.text('Минимум 8 символов'), findsWidgets);
      expect(auth.resetCalls, isEmpty);
    });

    testWidgets('10. mismatch is refused', (tester) async {
      final auth = await _pumpLogin(tester);
      await _toPasswordStep(tester);
      await tester.enterText(_key('reset-new-password'), 'newpassword1');
      await tester.enterText(_key('reset-repeat-password'), 'newpassword2');
      await _tapVisible(tester, 'reset-submit');
      expect(find.text('Пароли не совпадают'), findsOneWidget);
      expect(auth.resetCalls, isEmpty);
    });

    testWidgets('11, 13. submit sends phone+code+new_password → success', (
      tester,
    ) async {
      final auth = await _pumpLogin(tester);
      await _toPasswordStep(tester);
      await tester.enterText(_key('reset-new-password'), 'newpassword1');
      await tester.enterText(_key('reset-repeat-password'), 'newpassword1');
      await _tapVisible(tester, 'reset-submit');
      await tester.pump();
      expect(auth.resetCalls, [
        {
          'phone': '+77011234545',
          'code': '123456',
          'new_password': 'newpassword1',
        },
      ]);
      expect(_key('step-success'), findsOneWidget);
      expect(find.text('Пароль успешно изменён'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('12. invalid_code → back to the code, OTP cleared, '
        'phone and new password kept', (tester) async {
      final auth = await _pumpLogin(
        tester,
        auth: _FakeAuth()..resetError = _invalidCode,
      );
      await _toPasswordStep(tester);
      await tester.enterText(_key('reset-new-password'), 'newpassword1');
      await tester.enterText(_key('reset-repeat-password'), 'newpassword1');
      await _tapVisible(tester, 'reset-submit');
      await tester.pump();

      expect(_key('step-code'), findsOneWidget);
      expect(find.text('Неверный или истёкший код'), findsOneWidget);
      expect(find.text('+7 701 ••• •• 45'), findsOneWidget);
      expect(
        tester.widget<TextField>(_key('otp-input')).controller!.text,
        isEmpty,
      );

      auth.resetError = null;
      await tester.enterText(_key('otp-input'), '654321');
      await tester.pump();
      await _tapVisible(tester, 'reset-code-continue');
      final kept = tester.widget<TextFormField>(
        find.descendant(
          of: _key('reset-new-password'),
          matching: find.byType(TextFormField),
        ),
      );
      expect(kept.controller!.text, 'newpassword1');
      await _tapVisible(tester, 'reset-submit');
      await tester.pump();
      expect(auth.resetCalls.last['code'], '654321');
      expect(_key('step-success'), findsOneWidget);
    });

    testWidgets('14. «Войти» → Login with the phone filled, password empty', (
      tester,
    ) async {
      await _pumpLogin(tester);
      await _toPasswordStep(tester);
      await tester.enterText(_key('reset-new-password'), 'newpassword1');
      await tester.enterText(_key('reset-repeat-password'), 'newpassword1');
      await _tapVisible(tester, 'reset-submit');
      await tester.pump();
      await _tapVisible(tester, 'reset-sign-in');
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(_key('step-success'), findsNothing);
      final fields = tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .toList();
      expect(fields[0].controller!.text, '8 701 123 45 45');
      expect(fields[1].controller!.text, isEmpty);
    });
  });

  testWidgets('15. system Back: password → code → phone → Login', (
    tester,
  ) async {
    await _pumpLogin(tester);
    await _toPasswordStep(tester);
    expect(_key('step-password'), findsOneWidget);

    await _systemBack(tester);
    expect(_key('step-code'), findsOneWidget);
    await _systemBack(tester);
    expect(_key('step-phone'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(_key('reset-phone')).controller!.text,
      '8 701 123 45 45',
    );
    await _systemBack(tester);
    expect(_key('step-phone'), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  group('16. RU/KZ/EN', () {
    for (final (locale, link, title, getCode, enterCode) in [
      (
        AppLocale.ru,
        'Забыли пароль?',
        'Восстановление пароля',
        'Получить код',
        'Введите код',
      ),
      (
        AppLocale.kz,
        'Құпиясөзді ұмыттыңыз ба?',
        'Құпиясөзді қалпына келтіру',
        'Код алу',
        'Кодты енгізіңіз',
      ),
      (
        AppLocale.en,
        'Forgot password?',
        'Password recovery',
        'Get code',
        'Enter code',
      ),
    ]) {
      testWidgets(locale.name, (tester) async {
        final auth = await _pumpLogin(tester, locale: locale);
        expect(find.text(link), findsOneWidget);
        await _openForgot(tester);
        expect(find.text(title), findsOneWidget);
        expect(find.text(getCode), findsOneWidget);
        await tester.enterText(_key('reset-phone'), '+77011234545');
        await _tapVisible(tester, 'reset-get-code');
        await tester.pump();
        expect(find.text(enterCode), findsWidgets);
        expect(auth.forgotCalls.single['lang'], locale.name);
      });
    }
  });

  group('17–20. every step: dark/light × 320/390 × keyboard, no overflow', () {
    for (final width in [320.0, 390.0]) {
      for (final name in ['dark', 'light']) {
        for (final keyboard in [0.0, 320.0]) {
          testWidgets('${width.toInt()}px $name keyboard=${keyboard > 0}', (
            tester,
          ) async {
            await _pumpLogin(
              tester,
              theme: name == 'dark' ? AppTheme.dark : AppTheme.light,
              size: Size(width, 700),
              keyboard: keyboard,
            );
            await _openForgot(tester);
            expect(tester.takeException(), isNull);
            await tester.enterText(_key('reset-phone'), '+77011234545');
            await _tapVisible(tester, 'reset-get-code');
            await tester.pump();
            expect(tester.takeException(), isNull);
            await tester.enterText(_key('otp-input'), '123456');
            await tester.pump();
            await _tapVisible(tester, 'reset-code-continue');
            expect(tester.takeException(), isNull);
            await tester.enterText(_key('reset-new-password'), 'newpassword1');
            await tester.enterText(
              _key('reset-repeat-password'),
              'newpassword1',
            );
            await _tapVisible(tester, 'reset-submit'); // reachable
            await tester.pump();
            expect(_key('step-success'), findsOneWidget);
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });

  group('rules', () {
    test('normalizeKzPhone mirrors the backend', () {
      expect(normalizeKzPhone('8 701 123 45 45'), '+77011234545');
      expect(normalizeKzPhone('+7 (701) 123-45-45'), '+77011234545');
      expect(normalizeKzPhone('77011234545'), '+77011234545');
      expect(normalizeKzPhone('123'), isNull);
      expect(normalizeKzPhone('+1 701 123 45 45'), isNull);
      expect(normalizeKzPhone('+7701123454512'), isNull);
    });

    test('maskKzPhone shows operator code and last two digits only', () {
      expect(maskKzPhone('+77011234545'), '+7 701 ••• •• 45');
    });

    test('newPasswordProblem', () {
      expect(
        newPasswordProblem('1234567', '1234567'),
        NewPasswordProblem.tooShort,
      );
      expect(
        newPasswordProblem('12345678', '12345679'),
        NewPasswordProblem.mismatch,
      );
      expect(newPasswordProblem('пароль12', 'пароль12'), isNull);
    });

    test('passwordResetFailureOf reads the backend codes', () {
      expect(
        passwordResetFailureOf(_invalidCode),
        PasswordResetFailure.invalidCode,
      );
      expect(
        passwordResetFailureOf(
          const ApiException(
            ApiErrorType.unknown,
            statusCode: 400,
            debugMessage: 'weak_password',
          ),
        ),
        PasswordResetFailure.weakPassword,
      );
      expect(
        passwordResetFailureOf(
          const ApiException(ApiErrorType.unknown, statusCode: 429),
        ),
        PasswordResetFailure.tooManyRequests,
      );
      expect(
        passwordResetFailureOf(Exception('x')),
        PasswordResetFailure.other,
      );
    });
  });
}
