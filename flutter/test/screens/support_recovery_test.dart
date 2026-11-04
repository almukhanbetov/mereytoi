import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/network/api_client.dart';
import 'package:mereytoi_app/core/network/api_exception.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/models/user.dart';
import 'package:mereytoi_app/screens/auth/login_screen.dart';
import 'package:mereytoi_app/screens/auth/backup_code_recovery_screen.dart';
import 'package:mereytoi_app/screens/auth/support_recovery_screen.dart';
import 'package:mereytoi_app/services/auth_service.dart';
import 'package:mereytoi_app/state/auth_provider.dart';
import 'package:mereytoi_app/state/locale_provider.dart';
import 'package:mereytoi_app/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _temp = 'ABCD-EFGH-JKMN-PQRS';
const _newBackup = 'Z9Y8-X7W6-V5T4-S3R2-Q1P0-NMKJ-HGFE';

User _user() => User.fromJson({
  'id': 7,
  'name': 'Айгерім',
  'email': 'a@test.kz',
  'phone': '+77001112233',
  'role': 'user',
  'status': 'active',
});

class _FakeAuth extends AuthService {
  _FakeAuth() : super(ApiClient.test(tokenProvider: () async => null));

  final requestCalls = <String>[];
  Object? requestError;
  final resetCalls = <Map<String, String>>[];
  Object? resetError;

  @override
  Future<bool> fetchPasswordResetConfig() async => false;

  @override
  Future<User> fetchMe() async => _user();

  @override
  Future<void> requestSupportRecovery({required String login}) async {
    requestCalls.add(login);
    if (requestError != null) throw requestError!;
  }

  @override
  Future<RecoveryAuthResult> recoverWithSupportCode({
    required String login,
    required String tempCode,
    required String newPassword,
  }) async {
    resetCalls.add({'login': login, 'code': tempCode, 'new': newPassword});
    if (resetError != null) throw resetError!;
    return (user: _user(), token: 'support-token', recoveryCode: _newBackup);
  }
}

class _RecordingStorage extends FlutterSecureStoragePlatform {
  final writes = <String, String>{};

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async => writes[key] = value;
  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async => writes[key];
  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => writes.containsKey(key);
  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async => writes.remove(key);
  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      writes.clear();
  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => writes;
}

Finder _key(String k) => find.byKey(ValueKey(k));

class _Harness {
  _Harness(this.auth, this.storage, this.container);
  final _FakeAuth auth;
  final _RecordingStorage storage;
  final ProviderContainer container;
}

Future<_Harness> _pump(
  WidgetTester tester,
  Widget screen, {
  AppLocale locale = AppLocale.ru,
  ThemeData? theme,
  Size size = const Size(390, 844),
}) async {
  SharedPreferences.setMockInitialValues({});
  final storage = _RecordingStorage();
  FlutterSecureStoragePlatform.instance = storage;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final fake = _FakeAuth();
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
  return _Harness(fake, storage, container);
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(_key(key));
  await tester.pumpAndSettle();
  await tester.tap(_key(key));
  await tester.pumpAndSettle();
}

Future<void> _fillTemp(WidgetTester tester) async {
  await tester.enterText(_key('temp-login'), 'a@test.kz');
  await tester.enterText(_key('temp-code'), _temp.toLowerCase());
  await tester.enterText(_key('temp-new-password'), 'NewPass123');
  await tester.enterText(_key('temp-confirm-password'), 'NewPass123');
}

ApiException _apiError(int status, String reason) => ApiException(
  ApiErrorType.unknown,
  statusCode: status,
  debugMessage: reason,
);

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });

  testWidgets('login → «Забыли пароль?» → «Не помню резервный код» → request '
      'with the typed login: only the neutral answer', (tester) async {
    final h = await _pump(tester, const LoginScreen());
    await tester.enterText(find.byType(TextFormField).first, 'a@test.kz');
    await _tap(tester, 'forgot-password-link');
    expect(_key('recovery-no-code'), findsOneWidget);
    expect(find.text('Не помню резервный код'), findsOneWidget);

    await _tap(tester, 'recovery-no-code');
    expect(find.text('Отправить запрос в поддержку'), findsOneWidget);
    await _tap(tester, 'support-submit');

    expect(h.auth.requestCalls, ['a@test.kz']);
    expect(
      find.text('Если аккаунт найден, запрос будет передан в поддержку.'),
      findsOneWidget,
    );
    expect(_key('support-submit'), findsNothing);
    // Nothing signs anyone in, and nothing promises an instant recovery.
    expect(h.container.read(authProvider), isNot(isA<AuthAuthenticated>()));
    expect(h.storage.writes, isEmpty);
    expect(find.textContaining('Это происходит не сразу'), findsOneWidget);
  });

  testWidgets('a phone always gets the "enter your email" hint, an email '
      'never does: it reveals nothing about the account', (tester) async {
    final h = await _pump(tester, const SupportRecoveryRequestScreen());
    await tester.enterText(_key('support-login'), '+7 700 111 22 33');
    await _tap(tester, 'support-submit');
    expect(_key('support-request-sent'), findsOneWidget);
    expect(_key('support-phone-hint'), findsOneWidget);

    await _tap(tester, 'support-use-email');
    expect(_key('support-submit'), findsOneWidget);
    expect(_key('support-phone-hint'), findsNothing);
    final field = tester.widget<TextFormField>(_key('support-login'));
    expect(field.controller!.text, isEmpty);

    await tester.enterText(_key('support-login'), 'a@test.kz');
    await _tap(tester, 'support-submit');
    expect(_key('support-request-sent'), findsOneWidget);
    expect(_key('support-phone-hint'), findsNothing);
    expect(h.auth.requestCalls, ['+7 700 111 22 33', 'a@test.kz']);
  });

  testWidgets('wrong code by phone suggests email; by email it does not', (
    tester,
  ) async {
    final h = await _pump(tester, const TempCodeRecoveryScreen());
    await _fillTemp(tester);
    h.auth.resetError = _apiError(400, 'invalid_recovery_code');
    await _tap(tester, 'temp-submit');
    expect(find.textContaining('нескольким аккаунтам'), findsNothing);

    await tester.enterText(_key('temp-login'), '+7 700 111 22 33');
    await _tap(tester, 'temp-submit');
    expect(find.textContaining('нескольким аккаунтам'), findsOneWidget);
  });

  testWidgets('request form: an empty login sends nothing', (tester) async {
    final h = await _pump(tester, const SupportRecoveryRequestScreen());
    await _tap(tester, 'support-submit');
    expect(h.auth.requestCalls, isEmpty);
    expect(find.text('Введите email или телефон'), findsOneWidget);
  });

  testWidgets('request form: rate limit and network errors read as sentences '
      'and the form stays', (tester) async {
    final h = await _pump(tester, const SupportRecoveryRequestScreen());
    await tester.enterText(_key('support-login'), 'a@test.kz');

    h.auth.requestError = _apiError(429, 'too_many_attempts');
    await _tap(tester, 'support-submit');
    expect(find.textContaining('Слишком много запросов'), findsOneWidget);
    expect(_key('support-request-sent'), findsNothing);

    h.auth.requestError = const ApiException(
      ApiErrorType.network,
      debugMessage: 'SocketException: failed host lookup',
    );
    await _tap(tester, 'support-submit');
    expect(find.text('Нет подключения к интернету'), findsOneWidget);
    expect(find.textContaining('SocketException'), findsNothing);

    h.auth.requestError = null;
    await _tap(tester, 'support-submit');
    expect(_key('support-request-sent'), findsOneWidget);
  });

  testWidgets('temporary code from the login screen: new password, backup '
      'code shown, signed in, back to the start', (tester) async {
    final h = await _pump(tester, const LoginScreen());
    await _tap(tester, 'forgot-password-link');
    await _tap(tester, 'recovery-no-code');
    await _tap(tester, 'support-have-code');
    expect(find.text('Временный код восстановления'), findsOneWidget);

    await _fillTemp(tester);
    await _tap(tester, 'temp-submit');
    expect(h.auth.resetCalls.single, {
      'login': 'a@test.kz',
      'code': _temp.toLowerCase(),
      'new': 'NewPass123',
    });
    // The session isn't active until the new backup code was seen.
    expect(find.text(_newBackup), findsOneWidget);
    expect(h.container.read(authProvider), isNot(isA<AuthAuthenticated>()));

    await _tap(tester, 'recovery-code-saved');
    await _tap(tester, 'recovery-code-done');
    expect(h.container.read(authProvider), isA<AuthAuthenticated>());
    expect(find.text('home page'), findsOneWidget);
    expect(_key('temp-submit'), findsNothing);
    // Only the session token is stored: no code, no password.
    expect(h.storage.writes.values, ['support-token']);
  });

  testWidgets('temporary code form validates before anything is sent', (
    tester,
  ) async {
    final h = await _pump(tester, const TempCodeRecoveryScreen());
    await _tap(tester, 'temp-submit');
    expect(find.text('Введите email или телефон'), findsOneWidget);
    expect(find.text('Введите временный код'), findsOneWidget);
    expect(find.text('Не короче 8 символов'), findsOneWidget);

    await tester.enterText(_key('temp-login'), 'a@test.kz');
    await tester.enterText(_key('temp-code'), _temp);
    await tester.enterText(_key('temp-new-password'), 'NewPass123');
    await tester.enterText(_key('temp-confirm-password'), 'Different1');
    await _tap(tester, 'temp-submit');
    expect(find.text('Пароли не совпадают'), findsOneWidget);
    expect(h.auth.resetCalls, isEmpty);
  });

  testWidgets('wrong or expired code and too many attempts: clear messages, '
      'no raw errors, no session', (tester) async {
    final h = await _pump(tester, const TempCodeRecoveryScreen());
    await _fillTemp(tester);

    h.auth.resetError = _apiError(400, 'invalid_recovery_code');
    await _tap(tester, 'temp-submit');
    expect(find.textContaining('неверный или больше не действует'), findsOne);
    expect(find.textContaining('invalid_recovery_code'), findsNothing);

    h.auth.resetError = _apiError(429, 'too_many_attempts');
    await _tap(tester, 'temp-submit');
    expect(find.textContaining('Слишком много попыток'), findsOneWidget);

    expect(h.storage.writes, isEmpty);
    expect(h.container.read(authProvider), isNot(isA<AuthAuthenticated>()));
  });

  testWidgets('the backup code flow is still there alongside the new link', (
    tester,
  ) async {
    await _pump(tester, const BackupCodeRecoveryScreen());
    expect(_key('recovery-code-input'), findsOneWidget);
    expect(_key('recovery-submit'), findsOneWidget);
    expect(_key('recovery-no-code'), findsOneWidget);
    expect(find.textContaining('напишите менеджеру'), findsNothing);
  });

  group('no overflow', () {
    for (final locale in AppLocale.values) {
      for (final dark in [false, true]) {
        for (final width in [320.0, 390.0, 430.0]) {
          final name = '${locale.name} ${dark ? 'dark' : 'light'} $width';

          testWidgets('$name: request and its answer', (tester) async {
            await _pump(
              tester,
              const SupportRecoveryRequestScreen(),
              locale: locale,
              theme: dark ? AppTheme.dark : AppTheme.light,
              size: Size(width, 700),
            );
            expect(tester.takeException(), isNull);
            await tester.enterText(_key('support-login'), '+7 700 111 22 33');
            await _tap(tester, 'support-submit');
            expect(_key('support-phone-hint'), findsOneWidget);
            expect(tester.takeException(), isNull);
          });

          testWidgets('$name: temporary code with errors', (tester) async {
            await _pump(
              tester,
              const TempCodeRecoveryScreen(),
              locale: locale,
              theme: dark ? AppTheme.dark : AppTheme.light,
              size: Size(width, 700),
            );
            await _tap(tester, 'temp-submit');
            expect(tester.takeException(), isNull);
          });

          testWidgets('$name: backup screen with the new link', (tester) async {
            await _pump(
              tester,
              const BackupCodeRecoveryScreen(),
              locale: locale,
              theme: dark ? AppTheme.dark : AppTheme.light,
              size: Size(width, 700),
            );
            await tester.ensureVisible(_key('recovery-no-code'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });
}
