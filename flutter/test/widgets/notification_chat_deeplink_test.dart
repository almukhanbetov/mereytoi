import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/network/api_client.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/models/app_notification.dart';
import 'package:mereytoi_app/models/user.dart';
import 'package:mereytoi_app/screens/manager_chat/manager_chat_screen.dart';
import 'package:mereytoi_app/screens/notifications/notifications_screen.dart';
import 'package:mereytoi_app/screens/provider_chat/provider_chat_screen.dart';
import 'package:mereytoi_app/state/auth_provider.dart';
import 'package:mereytoi_app/state/notification_providers.dart';
import 'package:mereytoi_app/state/providers.dart';
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

/// Answers the handful of routes a notification tap touches: mark-read,
/// the unread badge, and fetching one conversation by id from either chat.
class _FakeAdapter implements HttpClientAdapter {
  final List<(String, String)> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add((options.method, options.path));
    final path = options.path;
    Object data;
    if (path.endsWith('/read')) {
      data = {
        'notification': {
          'id': int.parse(path.split('/')[3]),
          'user_id': 9,
          'type': 'x',
          'is_read': true,
          'created_at': '2026-01-01T00:00:00Z',
        },
      };
    } else if (path == '/api/notifications/unread-count') {
      data = {'count': 0};
    } else if (path == '/api/manager-chat/12') {
      data = {
        'conversation': {
          'id': 12,
          'user_id': 9,
          'listing_id': 5,
          'status': 'open',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        },
        'messages': [
          {
            'id': 1,
            'conversation_id': 12,
            'sender_type': 'manager',
            'body': 'Да, свободны!',
            'created_at': '2026-01-01T00:01:00Z',
          },
        ],
      };
    } else if (path == '/api/provider-chat/4') {
      data = {
        'conversation': {
          'id': 4,
          'provider_id': 2,
          'customer_user_id': 9,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        },
        'messages': [
          {
            'id': 1,
            'conversation_id': 4,
            'sender_user_id': 50,
            'body': 'Добрый день!',
            'created_at': '2026-01-01T00:01:00Z',
          },
        ],
      };
    } else {
      throw StateError('unhandled fake route: ${options.method} $path');
    }
    return ResponseBody.fromBytes(
      Uint8List.fromList(utf8.encode(jsonEncode(data))),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
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

AppNotification _notif(
  int id,
  String type,
  String entityType,
  int entityId,
  Map<String, dynamic> payload,
) => AppNotification(
  id: id,
  userId: 9,
  type: type,
  entityType: entityType,
  entityId: entityId,
  payload: payload,
  isRead: false,
  createdAt: DateTime.now(),
);

Future<(ProviderContainer, _FakeAdapter)> _pump(
  WidgetTester tester,
  List<AppNotification> notifications,
) async {
  FlutterSecureStoragePlatform.instance = _EmptySecureStoragePlatform();
  SharedPreferences.setMockInitialValues({});
  final adapter = _FakeAdapter();
  final client = ApiClient.test(tokenProvider: () async => 'test-token');
  client.debugDio.httpClientAdapter = adapter;
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(client),
      notificationsProvider.overrideWith(
        (ref) async => (notifications, notifications.length),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark,
        home: const NotificationsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  while (container.read(authProvider) is AuthLoading ||
      container.read(authProvider) is AuthInitial) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  container.read(authProvider.notifier).state = AuthAuthenticated(_user);
  await tester.pumpAndSettle();
  return (container, adapter);
}

void main() {
  testWidgets(
    'a manager reply notification marks read and opens that exact conversation',
    (tester) async {
      final (container, adapter) = await _pump(tester, [
        _notif(1, 'manager_message_received', 'manager_conversation', 12, {
          'body': 'Да, свободны!',
          'listing_id': 5,
        }),
      ]);

      expect(
        find.text('Новое сообщение от менеджера: «Да, свободны!»'),
        findsOneWidget,
      );
      await tester.tap(find.textContaining('Новое сообщение от менеджера'));
      await tester.pumpAndSettle();

      expect(find.byType(ManagerChatScreen), findsOneWidget);
      expect(adapter.requests, contains(('POST', '/api/notifications/1/read')));
      expect(adapter.requests, contains(('GET', '/api/manager-chat/12')));
      expect(
        adapter.requests.where((r) => r.$2 == '/api/manager-chat/start'),
        isEmpty,
      );
      expect(find.text('Да, свободны!'), findsOneWidget);

      // The opened chat started its 5s poll Timer — dispose synchronously,
      // before flutter_test's end-of-test pending-timer check (same as
      // manager_chat_screen_test.dart).
      container.dispose();
    },
  );

  testWidgets(
    'a provider message notification opens ProviderChatScreen by conversation id',
    (tester) async {
      final (container, adapter) = await _pump(tester, [
        _notif(2, 'provider_message_received', 'provider_conversation', 4, {
          'body': 'Добрый день!',
          'provider_id': 2,
          'sender_name': 'Ерлан Events',
        }),
      ]);

      expect(
        find.text('Новое сообщение от Ерлан Events: «Добрый день!»'),
        findsOneWidget,
      );
      await tester.tap(find.textContaining('Ерлан Events'));
      await tester.pumpAndSettle();

      final screen = tester.widget<ProviderChatScreen>(
        find.byType(ProviderChatScreen),
      );
      expect(screen.conversationId, 4);
      expect(screen.providerId, 2);
      expect(screen.peerName, 'Ерлан Events');
      expect(adapter.requests, contains(('POST', '/api/notifications/2/read')));
      expect(adapter.requests, contains(('GET', '/api/provider-chat/4')));
      expect(
        adapter.requests.where((r) => r.$2 == '/api/provider-chat/start'),
        isEmpty,
      );

      container.dispose();
    },
  );

  testWidgets(
    'the admin-side customer-message notification renders but stays put',
    (tester) async {
      await _pump(tester, [
        _notif(3, 'manager_chat_user_message', 'manager_conversation', 12, {
          'body': 'Вопрос',
        }),
      ]);

      await tester.tap(find.textContaining('Новое сообщение клиента'));
      await tester.pumpAndSettle();

      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(find.byType(ManagerChatScreen), findsNothing);
    },
  );
}
