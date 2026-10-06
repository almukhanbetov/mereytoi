import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/network/api_client.dart';
import 'package:mereytoi_app/core/network/api_exception.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/models/event.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/models/user.dart';
import 'package:mereytoi_app/screens/profile/change_password_screen.dart';
import 'package:mereytoi_app/screens/profile/profile_screen.dart';
import 'package:mereytoi_app/services/auth_service.dart';
import 'package:mereytoi_app/state/auth_provider.dart';
import 'package:mereytoi_app/state/event_providers.dart';
import 'package:mereytoi_app/state/listings_provider.dart';
import 'package:mereytoi_app/state/locale_provider.dart';
import 'package:mereytoi_app/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Secure storage that remembers what was written — where the session
/// token lives (TokenStorage).
class _RecordingSecureStorage extends FlutterSecureStoragePlatform {
  final values = <String, String>{};

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => values.containsKey(key);
  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async => values.remove(key);
  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      values.clear();
  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async => values[key];
  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => Map.of(values);
  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async => values[key] = value;
}

const _tokenKey = 'mereytoi_auth_token';

class _FakeAuth extends AuthService {
  _FakeAuth() : super(ApiClient.test(tokenProvider: () async => null));

  bool available = true;
  Object? configError;

  int codeRequests = 0;
  Object? codeError;
  Completer<void>? codeGate;

  final changeCalls = <Map<String, String?>>[];
  Object? changeError;
  Completer<void>? changeGate;

  @override
  Future<bool> fetchPasswordResetConfig() async {
    if (configError != null) throw configError!;
    return available;
  }

  @override
  Future<({int resendAfter, String phoneHint})> requestPasswordChangeCode({
    required String lang,
  }) async {
    codeRequests++;
    if (codeGate != null) await codeGate!.future;
    if (codeError != null) throw codeError!;
    return (resendAfter: 60, phoneHint: '+7 ••• ••• 45 45');
  }

  @override
  Future<String> changePassword({
    String? currentPassword,
    String? code,
    required String newPassword,
  }) async {
    changeCalls.add({
      'current_password': currentPassword,
      'code': code,
      'new_password': newPassword,
    });
    if (changeGate != null) await changeGate!.future;
    if (changeError != null) throw changeError!;
    return 'new-session-token';
  }
}

User _user({String phone = '+7 701 123 45 45', String status = 'active'}) =>
    User(
      id: 9,
      name: 'Алия',
      email: 'aliya@example.com',
      phone: phone,
      role: 'user',
      status: status,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

ApiException _err(int status, [String? code]) =>
    ApiException(ApiErrorType.unknown, statusCode: status, debugMessage: code);

Finder _key(String k) => find.byKey(ValueKey(k));

class _Env {
  _Env(this.container, this.auth, this.storage);
  final ProviderContainer container;
  final _FakeAuth auth;
  final _RecordingSecureStorage storage;
}

/// Pumps [home] (Profile by default) for a signed-in [user], with the old
/// session token already stored.
Future<_Env> _pump(
  WidgetTester tester, {
  Widget home = const ProfileScreen(),
  _FakeAuth? auth,
  User? user,
  AppLocale locale = AppLocale.ru,
  ThemeData? theme,
  Size size = const Size(390, 844),
  double keyboard = 0,
}) async {
  final storage = _RecordingSecureStorage();
  FlutterSecureStoragePlatform.instance = storage;
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);

  final fake = auth ?? _FakeAuth();
  final container = ProviderContainer(
    overrides: [
      authServiceProvider.overrideWithValue(fake),
      eventsProvider.overrideWith((ref) => Future.value(const <Event>[])),
      myListingsProvider.overrideWith((ref) => Future.value(const <Listing>[])),
    ],
  );
  addTearDown(container.dispose);
  container.read(localeProvider.notifier).setLocale(locale);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: theme ?? AppTheme.dark, home: home),
    ),
  );
  await tester.pump();
  while (container.read(authProvider) is AuthLoading ||
      container.read(authProvider) is AuthInitial) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  storage.values[_tokenKey] = 'old-session-token';
  container.read(authProvider.notifier).state = AuthAuthenticated(
    user ?? _user(),
  );
  await tester.pump();
  await tester.pump();
  return _Env(container, fake, storage);
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(_key(key));
  await tester.pump();
  await tester.tap(_key(key));
  await tester.pump();
}

Future<void> _systemBack(WidgetTester tester) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
    (_) {},
  );
  await tester.pumpAndSettle();
}

/// Profile → Безопасность → Изменить пароль.
Future<void> _openFromProfile(WidgetTester tester) async {
  await tester.ensureVisible(_key('profile-change-password'));
  await tester.tap(_key('profile-change-password'));
  await tester.pumpAndSettle();
}

Future<void> _fillNew(WidgetTester tester, String a, String b) async {
  await tester.enterText(_key('change-new-password'), a);
  await tester.enterText(_key('change-repeat-password'), b);
}

/// Variant B up to the code step.
Future<void> _toCode(WidgetTester tester) async {
  await _tap(tester, 'change-option-code');
  await _tap(tester, 'change-send-code');
  await tester.pump();
}

void main() {
  group('Profile', () {
    testWidgets('1, 2. Безопасность → Изменить пароль opens the screen', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.text('Безопасность'), findsOneWidget);
      expect(find.text('Изменить пароль'), findsOneWidget);
      await _openFromProfile(tester);
      expect(find.byType(ChangePasswordScreen), findsOneWidget);
      expect(_key('change-step-choose'), findsOneWidget);
    });

    testWidgets('pending (onboarding) account: no Security section', (
      tester,
    ) async {
      await _pump(tester, user: _user(status: 'pending'));
      await tester.pumpAndSettle(); // let the profile's entry animations end
      expect(find.text('Безопасность'), findsNothing);
      expect(_key('profile-change-password'), findsNothing);
    });
  });

  group('Choice', () {
    testWidgets('3, 4. both variants; B shows the masked profile phone', (
      tester,
    ) async {
      await _pump(tester, home: const ChangePasswordScreen());
      expect(find.text('Я помню текущий пароль'), findsOneWidget);
      expect(find.text('Я не помню текущий пароль'), findsOneWidget);
      expect(find.text('Код в WhatsApp на +7 701 ••• •• 45'), findsOneWidget);
      expect(find.textContaining('1234545'), findsNothing);
    });

    for (final (name, mutate, user) in [
      ('delivery off', (_FakeAuth a) => a.available = false, null),
      (
        'config error',
        (_FakeAuth a) =>
            a.configError = const ApiException(ApiErrorType.network),
        null,
      ),
      ('no phone in profile', (_FakeAuth a) {}, _user(phone: '')),
    ]) {
      testWidgets('4. variant B disabled when $name; A still works', (
        tester,
      ) async {
        final auth = _FakeAuth();
        mutate(auth);
        await _pump(
          tester,
          home: const ChangePasswordScreen(),
          auth: auth,
          user: user,
        );
        await tester.tap(_key('change-option-code'), warnIfMissed: false);
        await tester.pump();
        expect(_key('change-step-choose'), findsOneWidget);
        expect(auth.codeRequests, 0);
        await _tap(tester, 'change-option-current');
        expect(_key('change-step-current'), findsOneWidget);
      });
    }
  });

  group('Variant A — current password', () {
    testWidgets('5, 6, 7. current required, new ≥ 8, repeat must match', (
      tester,
    ) async {
      final env = await _pump(tester, home: const ChangePasswordScreen());
      await _tap(tester, 'change-option-current');

      await _fillNew(tester, 'newpassword1', 'newpassword1');
      await _tap(tester, 'change-submit-current');
      expect(find.text('Введите текущий пароль'), findsOneWidget);

      await tester.enterText(_key('change-current-password'), 'oldpassword1');
      await _fillNew(tester, 'short', 'short');
      await _tap(tester, 'change-submit-current');
      expect(find.text('Минимум 8 символов'), findsOneWidget);

      await _fillNew(tester, 'newpassword1', 'newpassword2');
      await _tap(tester, 'change-submit-current');
      expect(find.text('Пароли не совпадают'), findsOneWidget);
      expect(env.auth.changeCalls, isEmpty);
    });

    testWidgets('8, 11, 12. correct current → payload, new JWT stored, '
        'still signed in, Done → Profile', (tester) async {
      final env = await _pump(tester);
      await _openFromProfile(tester);
      await _tap(tester, 'change-option-current');
      await tester.enterText(_key('change-current-password'), 'oldpassword1');
      await _fillNew(tester, 'newpassword1', 'newpassword1');
      await _tap(tester, 'change-submit-current');
      await tester.pump();

      expect(env.auth.changeCalls, [
        {
          'current_password': 'oldpassword1',
          'code': null,
          'new_password': 'newpassword1',
        },
      ]);
      expect(env.storage.values[_tokenKey], 'new-session-token');
      expect(env.container.read(authProvider), isA<AuthAuthenticated>());
      expect(find.text('Пароль успешно изменён'), findsOneWidget);

      await _tap(tester, 'change-done');
      await tester.pumpAndSettle();
      expect(find.byType(ChangePasswordScreen), findsNothing);
      expect(find.text('Безопасность'), findsOneWidget);
    });

    testWidgets('loading state blocks a double submit', (tester) async {
      final auth = _FakeAuth()..changeGate = Completer<void>();
      final env = await _pump(
        tester,
        home: const ChangePasswordScreen(),
        auth: auth,
      );
      await _tap(tester, 'change-option-current');
      await tester.enterText(_key('change-current-password'), 'oldpassword1');
      await _fillNew(tester, 'newpassword1', 'newpassword1');
      await _tap(tester, 'change-submit-current');
      await tester.tap(_key('change-submit-current'), warnIfMissed: false);
      await tester.pump();
      expect(env.auth.changeCalls, hasLength(1));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      auth.changeGate!.complete();
      await tester.pump();
      await tester.pump();
      expect(_key('change-step-success'), findsOneWidget);
    });

    testWidgets('9. wrong current password: message, new password kept, '
        'old token untouched', (tester) async {
      final env = await _pump(
        tester,
        home: const ChangePasswordScreen(),
        auth: _FakeAuth()..changeError = _err(400, 'wrong_current_password'),
      );
      await _tap(tester, 'change-option-current');
      await tester.enterText(_key('change-current-password'), 'wrongpass1');
      await _fillNew(tester, 'newpassword1', 'newpassword1');
      await _tap(tester, 'change-submit-current');
      await tester.pump();
      expect(find.text('Неверный текущий пароль'), findsOneWidget);
      final kept = tester.widget<TextFormField>(
        find.descendant(
          of: _key('change-new-password'),
          matching: find.byType(TextFormField),
        ),
      );
      expect(kept.controller!.text, 'newpassword1');
      expect(env.storage.values[_tokenKey], 'old-session-token');
    });

    testWidgets('10. 429 → neutral "too many attempts"', (tester) async {
      await _pump(
        tester,
        home: const ChangePasswordScreen(),
        auth: _FakeAuth()..changeError = _err(429, 'too_many_requests'),
      );
      await _tap(tester, 'change-option-current');
      await tester.enterText(_key('change-current-password'), 'oldpassword1');
      await _fillNew(tester, 'newpassword1', 'newpassword1');
      await _tap(tester, 'change-submit-current');
      await tester.pump();
      expect(
        find.text('Слишком много попыток. Попробуйте позже.'),
        findsOneWidget,
      );
    });
  });

  group('Variant B — code', () {
    testWidgets('13, 14. requests a code; never asks for the phone', (
      tester,
    ) async {
      final env = await _pump(tester, home: const ChangePasswordScreen());
      await _tap(tester, 'change-option-code');
      expect(_key('change-step-send'), findsOneWidget);
      expect(
        find.text('Код будет отправлен на номер, указанный в вашем профиле.'),
        findsOneWidget,
      );
      expect(find.text('+7 701 ••• •• 45'), findsOneWidget);
      expect(find.byType(TextField), findsNothing); // no phone input
      await _tap(tester, 'change-send-code');
      await tester.pump();
      expect(env.auth.codeRequests, 1);
      expect(_key('change-step-code'), findsOneWidget);
    });

    testWidgets('15, 16. 6-digit code; resend after the countdown', (
      tester,
    ) async {
      final env = await _pump(tester, home: const ChangePasswordScreen());
      await _toCode(tester);
      final next = _key('change-code-continue');
      expect(tester.widget<ElevatedButton>(next).onPressed, isNull);
      await tester.enterText(_key('otp-input'), '12x3456');
      await tester.pump();
      expect(tester.widget<ElevatedButton>(next).onPressed, isNotNull);

      expect(find.text('Повторно отправить через 01:00'), findsOneWidget);
      await tester.pump(const Duration(seconds: 60));
      env.auth.codeGate = Completer<void>();
      await _tap(tester, 'change-resend');
      await tester.tap(_key('change-resend'), warnIfMissed: false);
      await tester.pump();
      expect(env.auth.codeRequests, 2); // one resend despite the double tap
      env.auth.codeGate!.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('Повторно отправить через 01:00'), findsOneWidget);
    });

    testWidgets('17, 19. code + new_password sent; new JWT stored', (
      tester,
    ) async {
      final env = await _pump(tester, home: const ChangePasswordScreen());
      await _toCode(tester);
      await tester.enterText(_key('otp-input'), '123456');
      await tester.pump();
      await _tap(tester, 'change-code-continue');
      await _fillNew(tester, 'newpassword1', 'newpassword1');
      await _tap(tester, 'change-submit-code');
      await tester.pump();
      expect(env.auth.changeCalls, [
        {
          'current_password': null,
          'code': '123456',
          'new_password': 'newpassword1',
        },
      ]);
      expect(env.storage.values[_tokenKey], 'new-session-token');
      expect(env.container.read(authProvider), isA<AuthAuthenticated>());
      expect(_key('change-step-success'), findsOneWidget);
    });

    testWidgets('18. invalid code → back to the code, cleared, password kept', (
      tester,
    ) async {
      final auth = _FakeAuth()..changeError = _err(400, 'invalid_code');
      await _pump(tester, home: const ChangePasswordScreen(), auth: auth);
      await _toCode(tester);
      await tester.enterText(_key('otp-input'), '123456');
      await tester.pump();
      await _tap(tester, 'change-code-continue');
      await _fillNew(tester, 'newpassword1', 'newpassword1');
      await _tap(tester, 'change-submit-code');
      await tester.pump();
      expect(_key('change-step-code'), findsOneWidget);
      expect(find.text('Неверный или истёкший код'), findsOneWidget);
      expect(
        tester.widget<TextField>(_key('otp-input')).controller!.text,
        isEmpty,
      );
      auth.changeError = null;
      await tester.enterText(_key('otp-input'), '654321');
      await tester.pump();
      await _tap(tester, 'change-code-continue');
      await _tap(tester, 'change-submit-code');
      await tester.pump();
      expect(auth.changeCalls.last['code'], '654321');
      expect(_key('change-step-success'), findsOneWidget);
    });

    testWidgets('delivery unavailable on send → message, stays on step', (
      tester,
    ) async {
      await _pump(
        tester,
        home: const ChangePasswordScreen(),
        auth: _FakeAuth()..codeError = _err(503),
      );
      await _toCode(tester);
      expect(_key('change-step-send'), findsOneWidget);
      expect(find.text('Отправка кода сейчас недоступна.'), findsOneWidget);
    });
  });

  testWidgets('25. system Back — A: form → choice → Profile; '
      'B: password → code → choice', (tester) async {
    await _pump(tester);
    await _openFromProfile(tester);
    await _tap(tester, 'change-option-current');
    await _systemBack(tester);
    expect(_key('change-step-choose'), findsOneWidget);
    await _systemBack(tester);
    expect(find.byType(ChangePasswordScreen), findsNothing);
    expect(find.text('Безопасность'), findsOneWidget);

    await _openFromProfile(tester);
    await _toCode(tester);
    await tester.enterText(_key('otp-input'), '123456');
    await tester.pump();
    await _tap(tester, 'change-code-continue');
    expect(_key('change-step-new'), findsOneWidget);
    await _systemBack(tester);
    expect(_key('change-step-code'), findsOneWidget);
    await _systemBack(tester);
    expect(_key('change-step-choose'), findsOneWidget);
    await _systemBack(tester);
    expect(find.byType(ChangePasswordScreen), findsNothing);
  });

  group('20. RU/KZ/EN', () {
    for (final (locale, security, change, know, forgot) in [
      (
        AppLocale.ru,
        'Безопасность',
        'Изменить пароль',
        'Я помню текущий пароль',
        'Я не помню текущий пароль',
      ),
      (
        AppLocale.kz,
        'Қауіпсіздік',
        'Құпиясөзді өзгерту',
        'Ағымдағы құпиясөзді білемін',
        'Ағымдағы құпиясөз есімде жоқ',
      ),
      (
        AppLocale.en,
        'Security',
        'Change password',
        'I know my current password',
        'I don\'t remember my current password',
      ),
    ]) {
      testWidgets(locale.name, (tester) async {
        await _pump(tester, locale: locale);
        expect(find.text(security), findsOneWidget);
        expect(find.text(change), findsWidgets);
        await _openFromProfile(tester);
        expect(find.text(know), findsOneWidget);
        expect(find.text(forgot), findsOneWidget);
      });
    }
  });

  group('21–24. dark/light × 320/390 × keyboard, both variants', () {
    for (final width in [320.0, 390.0]) {
      for (final name in ['dark', 'light']) {
        for (final keyboard in [0.0, 320.0]) {
          testWidgets('${width.toInt()}px $name keyboard=${keyboard > 0}', (
            tester,
          ) async {
            final theme = name == 'dark' ? AppTheme.dark : AppTheme.light;
            await _pump(
              tester,
              home: const ChangePasswordScreen(),
              theme: theme,
              size: Size(width, 700),
              keyboard: keyboard,
            );
            expect(tester.takeException(), isNull);
            // A
            await _tap(tester, 'change-option-current');
            await tester.enterText(
              _key('change-current-password'),
              'oldpassword1',
            );
            await _fillNew(tester, 'newpassword1', 'newpassword1');
            expect(tester.takeException(), isNull);
            await _tap(tester, 'change-submit-current'); // reachable
            await tester.pump();
            expect(_key('change-step-success'), findsOneWidget);
            expect(tester.takeException(), isNull);
          });

          testWidgets('B ${width.toInt()}px $name keyboard=${keyboard > 0}', (
            tester,
          ) async {
            final theme = name == 'dark' ? AppTheme.dark : AppTheme.light;
            await _pump(
              tester,
              home: const ChangePasswordScreen(),
              theme: theme,
              size: Size(width, 700),
              keyboard: keyboard,
            );
            await _toCode(tester);
            expect(tester.takeException(), isNull);
            await tester.enterText(_key('otp-input'), '123456');
            await tester.pump();
            await _tap(tester, 'change-code-continue');
            await _fillNew(tester, 'newpassword1', 'newpassword1');
            await _tap(tester, 'change-submit-code');
            await tester.pump();
            expect(_key('change-step-success'), findsOneWidget);
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });
}
