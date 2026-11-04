import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/network/api_client.dart';
import 'package:mereytoi_app/core/network/api_exception.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/screens/auth/email_otp_recovery_screen.dart';
import 'package:mereytoi_app/screens/auth/login_screen.dart';
import 'package:mereytoi_app/screens/auth/password_recovery_options_screen.dart';
import 'package:mereytoi_app/services/auth_service.dart';
import 'package:mereytoi_app/state/locale_provider.dart';
import 'package:mereytoi_app/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAuth extends AuthService {
  _FakeAuth({this.emailAvailable = true})
    : super(ApiClient.test(tokenProvider: () async => null));

  final bool emailAvailable;

  /// When set, requests stay in flight until it completes.
  Completer<void>? gate;
  final requests = <String>[];
  final langs = <String>[];
  Object? requestError;
  final resets = <Map<String, String>>[];
  Object? resetError;

  @override
  Future<bool> fetchPasswordResetConfig() async => false;

  @override
  Future<bool> fetchEmailOtpAvailable() async => emailAvailable;

  @override
  Future<void> requestEmailOtp({
    required String email,
    required String lang,
  }) async {
    requests.add(email);
    langs.add(lang);
    await gate?.future;
    if (requestError != null) throw requestError!;
  }

  @override
  Future<void> resetWithEmailOtp({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    resets.add({'email': email, 'otp': otp, 'new': newPassword});
    await gate?.future;
    if (resetError != null) throw resetError!;
  }
}

Finder _key(String k) => find.byKey(ValueKey(k));

Future<_FakeAuth> _pump(
  WidgetTester tester,
  Widget screen, {
  _FakeAuth? auth,
  AppLocale locale = AppLocale.ru,
  ThemeData? theme,
  Size size = const Size(390, 844),
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
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
        theme: theme ?? AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const ValueKey('open'),
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => screen)),
                child: const Text('home page'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(_key('open'));
  await tester.pumpAndSettle();
  return fake;
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(_key(key));
  await tester.pump();
  await tester.tap(_key(key));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _fillReset(WidgetTester tester, {String code = '042137'}) async {
  await tester.enterText(_key('otp-code'), code);
  await tester.enterText(_key('otp-new-password'), 'NewPass123');
  await tester.enterText(_key('otp-confirm-password'), 'NewPass123');
}

ApiException _apiError(int status, String reason) => ApiException(
  ApiErrorType.unknown,
  statusCode: status,
  debugMessage: reason,
);

/// Leaves no periodic timer behind when a test ends on the code step.
Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });

  testWidgets('the choice offers email, backup code and no access', (
    tester,
  ) async {
    await _pump(tester, const PasswordRecoveryOptionsScreen());
    expect(find.text('Получить код на email'), findsOneWidget);
    expect(find.text('У меня есть резервный код'), findsOneWidget);
    expect(
      find.text('Нет доступа к email / не помню резервный код'),
      findsOneWidget,
    );
  });

  testWidgets('without mail on the backend, email is not offered and the rest '
      'still is', (tester) async {
    await _pump(
      tester,
      const PasswordRecoveryOptionsScreen(),
      auth: _FakeAuth(emailAvailable: false),
    );
    expect(_key('forgot-email-code'), findsNothing);
    expect(_key('forgot-have-code'), findsOneWidget);
    expect(find.text('Не помню резервный код'), findsOneWidget);
  });

  testWidgets('the existing flows are reachable from the choice', (
    tester,
  ) async {
    await _pump(tester, const PasswordRecoveryOptionsScreen());
    await _tap(tester, 'forgot-have-code');
    expect(_key('recovery-code-input'), findsOneWidget);
    Navigator.of(tester.element(_key('recovery-code-input'))).pop();
    await tester.pumpAndSettle();
    await _tap(tester, 'forgot-support');
    expect(_key('support-submit'), findsOneWidget);
  });

  testWidgets('whole flow from login: typed email carried, neutral answer, new '
      'password, back on login with the email filled in', (tester) async {
    final auth = await _pump(tester, const LoginScreen());
    await tester.enterText(find.byType(TextFormField).first, 'a@test.kz');
    await _tap(tester, 'forgot-password-link');
    await _tap(tester, 'forgot-email-code');
    final email = tester.widget<TextFormField>(_key('otp-email'));
    expect(email.controller!.text, 'a@test.kz');

    await _tap(tester, 'otp-send');
    expect(auth.requests, ['a@test.kz']);
    expect(auth.langs, ['ru']);
    expect(find.textContaining('Если аккаунт с таким email найден'), findsOne);
    expect(find.text('Отправить ещё раз через 60 с'), findsOneWidget);

    await _fillReset(tester);
    await _tap(tester, 'otp-submit');
    await tester.pump(const Duration(milliseconds: 400));
    expect(auth.resets.single, {
      'email': 'a@test.kz',
      'otp': '042137',
      'new': 'NewPass123',
    });
    expect(_key('otp-submit'), findsNothing);
    expect(
      find.text('Пароль изменён. Войдите с новым паролем.'),
      findsOneWidget,
    );
    final identifier = tester.widget<TextFormField>(
      find.byType(TextFormField).first,
    );
    expect(identifier.controller!.text, 'a@test.kz');
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('double taps open one flow, send one request, reset once', (
    tester,
  ) async {
    final auth = _FakeAuth();
    await _pump(
      tester,
      const PasswordRecoveryOptionsScreen(initialLogin: 'a@test.kz'),
      auth: auth,
    );
    await tester.pump();
    await tester.tap(_key('forgot-email-code'));
    await tester.tap(_key('forgot-email-code'));
    await tester.pumpAndSettle();
    expect(find.byType(EmailOtpRecoveryScreen), findsOneWidget);

    auth.gate = Completer<void>();
    await tester.tap(_key('otp-send'));
    await tester.tap(_key('otp-send'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(auth.requests, hasLength(1));
    auth.gate!.complete();
    auth.gate = null;
    await tester.pump();
    await tester.pump();

    await _fillReset(tester);
    auth.gate = Completer<void>();
    await tester.tap(_key('otp-submit'));
    await tester.tap(_key('otp-submit'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(auth.resets, hasLength(1));
    auth.resetError = _apiError(400, 'invalid_recovery_code');
    auth.gate!.complete();
    await tester.pump();
    await tester.pump();
    await _finish(tester);
  });

  testWidgets('the email is validated before anything is sent', (tester) async {
    final auth = await _pump(tester, const EmailOtpRecoveryScreen());
    await _tap(tester, 'otp-send');
    expect(find.text('Введите email'), findsOneWidget);
    await tester.enterText(_key('otp-email'), 'not-an-email');
    await _tap(tester, 'otp-send');
    expect(find.text('Введите email'), findsOneWidget);
    expect(auth.requests, isEmpty);
  });

  testWidgets(
    'code and passwords are validated; the code takes 6 digits only',
    (tester) async {
      final auth = await _pump(
        tester,
        const EmailOtpRecoveryScreen(initialEmail: 'a@test.kz'),
      );
      await _tap(tester, 'otp-send');
      await _tap(tester, 'otp-submit');
      expect(find.text('Введите 6 цифр из письма'), findsOneWidget);
      expect(find.text('Не короче 8 символов'), findsOneWidget);

      await tester.enterText(_key('otp-code'), '12ab34567890');
      final code = tester.widget<TextFormField>(_key('otp-code'));
      expect(code.controller!.text, '123456');
      await tester.enterText(_key('otp-new-password'), 'NewPass123');
      await tester.enterText(_key('otp-confirm-password'), 'Different1');
      await _tap(tester, 'otp-submit');
      expect(find.text('Пароли не совпадают'), findsOneWidget);
      expect(auth.resets, isEmpty);
      await _finish(tester);
    },
  );

  testWidgets('resend is locked for 60 seconds, counts down, then asks again '
      'and clears the old code', (tester) async {
    final auth = await _pump(
      tester,
      const EmailOtpRecoveryScreen(initialEmail: 'a@test.kz'),
    );
    await _tap(tester, 'otp-send');
    TextButton resend() => tester.widget<TextButton>(_key('otp-resend'));
    expect(resend().onPressed, isNull);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Отправить ещё раз через 58 с'), findsOneWidget);
    await tester.enterText(_key('otp-code'), '111111');

    for (var i = 0; i < 58; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text('Отправить код ещё раз'), findsOneWidget);
    expect(resend().onPressed, isNotNull);
    await _tap(tester, 'otp-resend');
    expect(auth.requests, hasLength(2));
    expect(find.text('Отправить ещё раз через 60 с'), findsOneWidget);
    final code = tester.widget<TextFormField>(_key('otp-code'));
    expect(code.controller!.text, isEmpty);
    await _finish(tester);
  });

  testWidgets('errors read as sentences, no raw codes; the form stays', (
    tester,
  ) async {
    final auth = await _pump(
      tester,
      const EmailOtpRecoveryScreen(initialEmail: 'a@test.kz'),
    );
    auth.requestError = _apiError(429, 'too_many_attempts');
    await _tap(tester, 'otp-send');
    expect(find.textContaining('Слишком много попыток'), findsOneWidget);
    expect(_key('otp-sent'), findsNothing);

    auth.requestError = null;
    await _tap(tester, 'otp-send');
    await _fillReset(tester);
    auth.resetError = _apiError(400, 'invalid_recovery_code');
    await _tap(tester, 'otp-submit');
    expect(find.textContaining('неверный или больше не действует'), findsOne);
    expect(find.textContaining('invalid_recovery_code'), findsNothing);
    expect(_key('otp-submit'), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('another email can be entered after sending', (tester) async {
    await _pump(
      tester,
      const EmailOtpRecoveryScreen(initialEmail: 'a@test.kz'),
    );
    await _tap(tester, 'otp-send');
    await _tap(tester, 'otp-change-email');
    expect(_key('otp-email'), findsOneWidget);
    expect(_key('otp-submit'), findsNothing);
    await _finish(tester);
  });

  group('no overflow', () {
    for (final locale in AppLocale.values) {
      for (final dark in [false, true]) {
        for (final width in [320.0, 390.0, 430.0]) {
          testWidgets('${locale.name} ${dark ? 'dark' : 'light'} $width', (
            tester,
          ) async {
            await _pump(
              tester,
              const PasswordRecoveryOptionsScreen(
                initialLogin: 'very.long.email.address.for.layout@example.com',
              ),
              locale: locale,
              theme: dark ? AppTheme.dark : AppTheme.light,
              size: Size(width, 700),
            );
            expect(tester.takeException(), isNull);
            await _tap(tester, 'forgot-email-code');
            expect(tester.takeException(), isNull);
            await _tap(tester, 'otp-send');
            expect(_key('otp-sent'), findsOneWidget);
            expect(tester.takeException(), isNull);
            await _tap(tester, 'otp-submit');
            expect(tester.takeException(), isNull);
            await _finish(tester);
          });
        }
      }
    }
  });
}
