import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/network/api_client.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/models/user.dart';
import 'package:mereytoi_app/screens/profile/change_password_screen.dart';
import 'package:mereytoi_app/services/auth_service.dart';
import 'package:mereytoi_app/state/auth_provider.dart';
import 'package:mereytoi_app/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Secure storage whose writes only land when [gate] is completed — a slow
/// keystore, to see what the app does while the new token isn't saved yet.
class _SlowStorage extends FlutterSecureStoragePlatform {
  final values = <String, String>{};
  Completer<void>? gate;

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
  }) async {
    if (gate != null) await gate!.future;
    values[key] = value;
  }
}

class _Auth extends AuthService {
  _Auth() : super(ApiClient.test(tokenProvider: () async => null));
  int calls = 0;

  @override
  Future<bool> fetchPasswordResetConfig() async => true;

  @override
  Future<String> changePassword({
    String? currentPassword,
    String? code,
    required String newPassword,
  }) async {
    calls++;
    return 'new-session-token';
  }
}

final _user = User(
  id: 1,
  name: 'A',
  email: 'a@b.kz',
  phone: '+77011234545',
  role: 'user',
  status: 'active',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

const _tokenKey = 'mereytoi_auth_token';

void main() {
  testWidgets('the new token is saved before the change counts as done: '
      'no success screen, no completion while the write is pending', (
    tester,
  ) async {
    final storage = _SlowStorage();
    FlutterSecureStoragePlatform.instance = storage;
    SharedPreferences.setMockInitialValues({});
    final auth = _Auth();
    final container = ProviderContainer(
      overrides: [authServiceProvider.overrideWithValue(auth)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const ChangePasswordScreen(),
        ),
      ),
    );
    while (container.read(authProvider) is AuthLoading ||
        container.read(authProvider) is AuthInitial) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    storage.values[_tokenKey] = 'old-session-token';
    container.read(authProvider.notifier).state = AuthAuthenticated(_user);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('change-option-current')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('change-current-password')),
      'oldpassword1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('change-new-password')),
      'newpassword1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('change-repeat-password')),
      'newpassword1',
    );

    storage.gate = Completer<void>(); // the keystore is slow
    await tester.ensureVisible(
      find.byKey(const ValueKey('change-submit-current')),
    );
    await tester.tap(find.byKey(const ValueKey('change-submit-current')));
    await tester.pump();
    await tester.pump();

    // Server already accepted the change, token not yet stored:
    expect(auth.calls, 1);
    expect(storage.values[_tokenKey], 'old-session-token');
    expect(find.byKey(const ValueKey('change-step-success')), findsNothing);
    expect(
      find.byType(CircularProgressIndicator),
      findsOneWidget,
    ); // still busy, can't resubmit
    await tester.tap(
      find.byKey(const ValueKey('change-submit-current')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(auth.calls, 1);

    storage.gate!.complete();
    await tester.pump();
    await tester.pump();

    expect(storage.values[_tokenKey], 'new-session-token');
    expect(find.byKey(const ValueKey('change-step-success')), findsOneWidget);
    expect(container.read(authProvider), isA<AuthAuthenticated>());
  });
}
