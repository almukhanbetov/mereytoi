import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/network/api_client.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/screens/manager_chat/manager_chat_screen.dart';
import 'package:mereytoi_app/screens/notifications/notifications_screen.dart';
import 'package:mereytoi_app/state/providers.dart';

/// Empty in-memory secure storage — `TokenStorage.instance.readToken()`
/// returns null, so the real `AuthNotifier` naturally settles on
/// `AuthUnauthenticated` with no HTTP call at all (see `AuthNotifier
/// ._restoreSession`'s own early-return for "no token").
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

/// Fails loudly instead of hanging/hitting the real network — brief
/// section 20's whole point is that a logged-out screen never makes an
/// API call that's a guaranteed 401; if one of these screens regresses and
/// does call something, this test should fail on *that*, not time out.
class _ExplodingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    throw StateError(
      'unexpected API call while logged out: ${options.method} ${options.path}',
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUp(() {
    FlutterSecureStoragePlatform.instance = _EmptySecureStoragePlatform();
  });

  List<Override> loggedOutOverrides() {
    final client = ApiClient.test(tokenProvider: () async => null);
    client.debugDio.httpClientAdapter = _ExplodingAdapter();
    return [apiClientProvider.overrideWithValue(client)];
  }

  testWidgets(
    'ManagerChatScreen shows a login prompt (and calls no API) when logged out',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: loggedOutOverrides(),
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const ManagerChatScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Войдите, чтобы написать менеджеру'), findsOneWidget);
    },
  );

  testWidgets(
    'NotificationsScreen shows a login prompt (and calls no API) when logged out',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: loggedOutOverrides(),
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const NotificationsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Войдите, чтобы видеть уведомления'), findsOneWidget);
    },
  );
}
