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
import 'package:mereytoi_app/screens/auth/register_screen.dart';
import 'package:mereytoi_app/screens/profile/recovery_code_settings_screen.dart';
import 'package:mereytoi_app/services/auth_service.dart';
import 'package:mereytoi_app/state/auth_provider.dart';
import 'package:mereytoi_app/state/locale_provider.dart';
import 'package:mereytoi_app/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _code = 'ABCD-EFGH-JKMN-PQRS-TVWX-YZ01-2345';
const _newCode = 'Z9Y8-X7W6-V5T4-S3R2-Q1P0-NMKJ-HGFE';

User _user() => User.fromJson({
  'id': 7,
  'name': 'Айгерім',
  'email': 'a@test.kz',
  'phone': '+77001112233',
  'role': 'user',
  'status': 'active',
});

/// Backend stand-in for registration, backup-code recovery and replacement.
class _FakeAuth extends AuthService {
  _FakeAuth() : super(ApiClient.test(tokenProvider: () async => null));

  bool whatsApp = false;
  bool? meHasCode;
  final recoverCalls = <Map<String, String>>[];
  Object? recoverError;
  final replaceCalls = <String>[];
  Object? replaceError;

  @override
  Future<bool> fetchPasswordResetConfig() async => whatsApp;

  @override
  Future<User> fetchMe() async => _user().copyWith(hasRecoveryCode: meHasCode);

  @override
  Future<RecoveryAuthResult> register({
    required String name,
    required String email,
    String phone = '',
    required String password,
  }) async => (user: _user(), token: 'reg-token', recoveryCode: _code);

  @override
  Future<RecoveryAuthResult> recoverWithCode({
    required String login,
    required String code,
    required String newPassword,
  }) async {
    recoverCalls.add({'login': login, 'code': code, 'new': newPassword});
    if (recoverError != null) throw recoverError!;
    return (user: _user(), token: 'rec-token', recoveryCode: _newCode);
  }

  @override
  Future<String> replaceRecoveryCode({required String currentPassword}) async {
    replaceCalls.add(currentPassword);
    if (replaceError != null) throw replaceError!;
    return _newCode;
  }
}

/// Records every secure-storage write: only the session token may be saved.
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

/// Pumps [screen] on top of a home page, so "closes itself" is observable.
Future<_Harness> _pump(
  WidgetTester tester,
  Widget screen, {
  _FakeAuth? auth,
  AppLocale locale = AppLocale.ru,
  ThemeData? theme,
  Size size = const Size(390, 844),
  bool signedIn = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final storage = _RecordingStorage();
  if (signedIn) storage.writes['mereytoi_auth_token'] = 'existing-token';
  FlutterSecureStoragePlatform.instance = storage;
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

/// Ticks "I saved it" and taps Done on the code screen.
Future<void> _confirmCode(WidgetTester tester) async {
  await _tap(tester, 'recovery-code-saved');
  await _tap(tester, 'recovery-code-done');
}

Future<void> _fillRecovery(WidgetTester tester) async {
  await tester.enterText(_key('recovery-login'), '8 700 111 22 33');
  await tester.enterText(_key('recovery-code-input'), _code.toLowerCase());
  await tester.enterText(_key('recovery-new-password'), 'NewPass123');
  await tester.enterText(_key('recovery-confirm-password'), 'NewPass123');
}

void main() {
  testWidgets('registration shows the backup code once, with copy and a '
      'warning, and signs in only after "I saved it"', (tester) async {
    final h = await _pump(tester, const RegisterScreen());
    await tester.enterText(find.byType(TextFormField).at(0), 'Айгерім');
    await tester.enterText(find.byType(TextFormField).at(1), 'a@test.kz');
    await tester.enterText(find.byType(TextFormField).at(3), 'secret12');
    final submit = find.widgetWithText(ElevatedButton, 'Зарегистрироваться');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(find.text(_code), findsOneWidget);
    expect(find.textContaining('Сохраните код в надёжном месте'), findsOne);
    expect(h.container.read(authProvider), isNot(isA<AuthAuthenticated>()));

    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    await _tap(tester, 'recovery-code-copy');
    expect(clipboard, _code);
    expect(find.text('Скопировано'), findsOneWidget);

    // Can't leave before confirming.
    final done = tester.widget<ElevatedButton>(_key('recovery-code-done'));
    expect(done.onPressed, isNull);
    await _confirmCode(tester);

    expect(h.container.read(authProvider), isA<AuthAuthenticated>());
    expect(find.text('home page'), findsOneWidget); // register closed
    // Only the session token was persisted — never the code.
    expect(h.storage.writes.values, ['reg-token']);
    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys()) {
      expect('${prefs.get(k)}', isNot(contains(_code)));
    }
  });

  testWidgets('«Забыли пароль?» → backup code + new password → new code '
      'shown → signed in, login closed', (tester) async {
    final h = await _pump(tester, const LoginScreen());
    expect(find.text('Забыли пароль?'), findsOneWidget);
    final link = tester.getSize(_key('forgot-password-link'));
    expect(link.height, greaterThanOrEqualTo(48));
    await _tap(tester, 'forgot-password-link');
    await _tap(tester, 'forgot-have-code');
    expect(_key('recovery-use-whatsapp'), findsNothing);

    await _fillRecovery(tester);
    await _tap(tester, 'recovery-submit');
    expect(h.auth.recoverCalls.single, {
      'login': '8 700 111 22 33',
      'code': _code.toLowerCase(),
      'new': 'NewPass123',
    });
    expect(find.text(_newCode), findsOneWidget);
    await _confirmCode(tester);

    expect(h.container.read(authProvider), isA<AuthAuthenticated>());
    expect(find.text('home page'), findsOneWidget);
    expect(h.storage.writes.values, ['rec-token']);
  });

  testWidgets('wrong code / unknown account: one neutral message; too many '
      'attempts: wait message; nothing signed in', (tester) async {
    final auth = _FakeAuth()
      ..recoverError = const ApiException(
        ApiErrorType.unknown,
        statusCode: 400,
        debugMessage: 'invalid_recovery_code',
      );
    final h = await _pump(tester, const LoginScreen(), auth: auth);
    await _tap(tester, 'forgot-password-link');
    await _tap(tester, 'forgot-have-code');
    await _fillRecovery(tester);
    await _tap(tester, 'recovery-submit');
    expect(
      find.text('Неверный резервный код или данные аккаунта'),
      findsOneWidget,
    );
    // The way out stays on screen next to the error.
    expect(_key('recovery-error').hitTestable(), findsOneWidget);
    expect(_key('recovery-no-code').hitTestable(), findsOneWidget);
    auth.recoverError = const ApiException(
      ApiErrorType.unknown,
      statusCode: 429,
      debugMessage: 'too_many_attempts',
    );
    await _tap(tester, 'recovery-submit');
    expect(find.textContaining('Слишком много попыток'), findsOneWidget);
    expect(h.container.read(authProvider), isNot(isA<AuthAuthenticated>()));
    expect(h.storage.writes, isEmpty);
  });

  testWidgets('new password is validated before anything is sent', (
    tester,
  ) async {
    final h = await _pump(tester, const LoginScreen());
    await _tap(tester, 'forgot-password-link');
    await _tap(tester, 'forgot-have-code');
    await tester.enterText(_key('recovery-login'), 'a@test.kz');
    await tester.enterText(_key('recovery-code-input'), _code);
    await tester.enterText(_key('recovery-new-password'), 'short');
    await tester.enterText(_key('recovery-confirm-password'), 'other');
    await _tap(tester, 'recovery-submit');
    expect(find.text('Не короче 8 символов'), findsOneWidget);
    expect(find.text('Пароли не совпадают'), findsOneWidget);
    expect(h.auth.recoverCalls, isEmpty);
  });

  testWidgets('WhatsApp flow stays reachable when the backend can deliver', (
    tester,
  ) async {
    await _pump(
      tester,
      const LoginScreen(),
      auth: _FakeAuth()..whatsApp = true,
    );
    await _tap(tester, 'forgot-password-link');
    await _tap(tester, 'forgot-have-code');
    expect(_key('recovery-code-input'), findsOneWidget);
    await _tap(tester, 'recovery-use-whatsapp');
    expect(_key('reset-phone'), findsOneWidget);
  });

  testWidgets('back from recovery returns to login', (tester) async {
    await _pump(tester, const LoginScreen());
    await _tap(tester, 'forgot-password-link');
    await _tap(tester, 'forgot-have-code');
    Navigator.of(tester.element(_key('recovery-code-input'))).pop();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(_key('forgot-password-link'), findsOneWidget);
  });

  testWidgets('old account without a code: says so, «Создать резервный '
      'код» needs no confirmation, the code is shown once, then the status '
      'flips', (tester) async {
    final auth = _FakeAuth()..meHasCode = false;
    final h = await _pump(
      tester,
      const RecoveryCodeSettingsScreen(),
      auth: auth,
      signedIn: true,
    );
    expect(_key('recovery-status-missing'), findsOneWidget);
    expect(find.textContaining('ещё не создан'), findsOneWidget);
    expect(find.text('Создать резервный код'), findsOneWidget);
    await tester.enterText(_key('recovery-settings-password'), 'secret12');
    await _tap(tester, 'recovery-settings-create');
    expect(find.byType(AlertDialog), findsNothing);
    expect(auth.replaceCalls, ['secret12']);
    expect(find.text(_newCode), findsOneWidget);
    expect(find.textContaining('показывается только сейчас'), findsOneWidget);
    await _confirmCode(tester);
    final auth0 = h.container.read(authProvider) as AuthAuthenticated;
    expect(auth0.user.hasRecoveryCode, isTrue);
    // The code never reaches storage.
    expect(h.storage.writes.values, ['existing-token']);
  });

  testWidgets('existing code: replacing asks first; cancel sends nothing; a '
      'wrong password is refused; confirm creates the new code', (
    tester,
  ) async {
    final auth = _FakeAuth()
      ..meHasCode = true
      ..replaceError = const ApiException(
        ApiErrorType.unknown,
        statusCode: 400,
        debugMessage: 'wrong_current_password',
      );
    await _pump(
      tester,
      const RecoveryCodeSettingsScreen(),
      auth: auth,
      signedIn: true,
    );
    expect(_key('recovery-status-true'), findsOneWidget);
    expect(find.text('Заменить код'), findsOneWidget);

    await tester.enterText(_key('recovery-settings-password'), 'wrong');
    await _tap(tester, 'recovery-settings-create');
    expect(find.text('Заменить резервный код?'), findsOneWidget);
    await _tap(tester, 'recovery-replace-cancel');
    expect(auth.replaceCalls, isEmpty);

    await _tap(tester, 'recovery-settings-create');
    await _tap(tester, 'recovery-replace-confirm');
    expect(find.text('Неверный текущий пароль'), findsOneWidget);

    auth.replaceError = null;
    await tester.enterText(_key('recovery-settings-password'), 'secret12');
    await _tap(tester, 'recovery-settings-create');
    await _tap(tester, 'recovery-replace-confirm');
    expect(auth.replaceCalls, ['wrong', 'secret12']);
    expect(find.text(_newCode), findsOneWidget);
    await _confirmCode(tester);
    expect(find.text('home page'), findsOneWidget);
  });

  testWidgets('registration needs 8+ characters, like every new password', (
    tester,
  ) async {
    await _pump(tester, const RegisterScreen());
    await tester.enterText(find.byType(TextFormField).at(0), 'Айгерім');
    await tester.enterText(find.byType(TextFormField).at(1), 'a@test.kz');
    await tester.enterText(find.byType(TextFormField).at(3), 'seven77');
    final submit = find.widgetWithText(ElevatedButton, 'Зарегистрироваться');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('Минимум 8 символов'), findsOneWidget);
    expect(find.text(_code), findsNothing);
  });

  group('RU/KZ/EN × light/dark × 320/390/430: no overflow', () {
    const links = {
      AppLocale.ru: 'Забыли пароль?',
      AppLocale.kz: 'Құпиясөзді ұмыттыңыз ба?',
      AppLocale.en: 'Forgot password?',
    };
    for (final locale in AppLocale.values) {
      for (final dark in [false, true]) {
        for (final width in [320.0, 390.0, 430.0]) {
          testWidgets('${locale.name} ${dark ? 'dark' : 'light'} '
              '${width.toInt()}', (tester) async {
            await _pump(
              tester,
              const LoginScreen(),
              locale: locale,
              theme: dark ? AppTheme.dark : AppTheme.light,
              size: Size(width, 700),
            );
            expect(find.text(links[locale]!), findsOneWidget);
            await _tap(tester, 'forgot-password-link');
            await _tap(tester, 'forgot-have-code');
            expect(tester.takeException(), isNull);
            await _fillRecovery(tester);
            await _tap(tester, 'recovery-submit');
            expect(find.text(_newCode), findsOneWidget);
            expect(tester.takeException(), isNull);
            await _confirmCode(tester);
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });

  group('settings screen: RU/KZ/EN × light/dark × 320/390/430', () {
    for (final locale in AppLocale.values) {
      for (final dark in [false, true]) {
        for (final width in [320.0, 390.0, 430.0]) {
          for (final hasCode in [false, true]) {
            testWidgets('${locale.name} ${dark ? 'dark' : 'light'} '
                '${width.toInt()} hasCode=$hasCode', (tester) async {
              await _pump(
                tester,
                const RecoveryCodeSettingsScreen(),
                auth: _FakeAuth()..meHasCode = hasCode,
                signedIn: true,
                locale: locale,
                theme: dark ? AppTheme.dark : AppTheme.light,
                size: Size(width, 700),
              );
              expect(tester.takeException(), isNull);
              await tester.enterText(
                _key('recovery-settings-password'),
                'secret12',
              );
              await _tap(tester, 'recovery-settings-create');
              if (hasCode) {
                expect(find.byType(AlertDialog), findsOneWidget);
                expect(tester.takeException(), isNull);
                await _tap(tester, 'recovery-replace-confirm');
              }
              expect(find.text(_newCode), findsOneWidget);
              expect(tester.takeException(), isNull);
            });
          }
        }
      }
    }
  });
}
