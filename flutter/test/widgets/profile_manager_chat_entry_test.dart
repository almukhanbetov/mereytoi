import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/models/event.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/models/user.dart';
import 'package:mereytoi_app/screens/manager_chat/manager_chat_screen.dart';
import 'package:mereytoi_app/screens/profile/profile_screen.dart';
import 'package:mereytoi_app/state/auth_provider.dart';
import 'package:mereytoi_app/state/event_providers.dart';
import 'package:mereytoi_app/state/listings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Этап 10Б-53, brief item 2 — "Доступ к чату из профиля" was missing
/// entirely (audit finding); this exercises the new "Написать менеджеру"
/// row under Профиль → Поддержка.
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

void main() {
  testWidgets(
    'Профиль shows "Написать менеджеру" and it opens ManagerChatScreen',
    (tester) async {
      FlutterSecureStoragePlatform.instance = _EmptySecureStoragePlatform();
      SharedPreferences.setMockInitialValues({});

      final container = ProviderContainer(
        overrides: [
          eventsProvider.overrideWith((ref) => Future.value(const <Event>[])),
          myListingsProvider.overrideWith(
            (ref) => Future.value(const <Listing>[]),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: AppTheme.dark, home: const ProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();
      // See `manager_chat_screen_test.dart`'s own note: a single
      // `pumpAndSettle()` doesn't guarantee `AuthNotifier`'s background
      // session-restore has actually finished — poll past it first so the
      // override below isn't silently clobbered afterward.
      while (container.read(authProvider) is AuthLoading ||
          container.read(authProvider) is AuthInitial) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      container.read(authProvider.notifier).state = AuthAuthenticated(_user);
      await tester.pumpAndSettle();

      final entry = find.text('Написать менеджеру');
      expect(entry, findsOneWidget);

      await tester.tap(entry);
      await tester.pumpAndSettle();

      expect(find.byType(ManagerChatScreen), findsOneWidget);
    },
  );
}
