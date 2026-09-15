import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/network/api_client.dart';
import 'package:mereytoi_app/state/notification_actions.dart';
import 'package:mereytoi_app/state/notification_providers.dart';
import 'package:mereytoi_app/state/providers.dart';

/// A stateful fake backend — mirrors the real handler's own behavior
/// closely enough to test that `NotificationActions` invalidates
/// `unreadNotificationCountProvider`/`notificationsProvider` correctly:
/// marking one (or all) read actually decrements what `unread-count`
/// returns afterward, via real request/response round trips.
class _FakeNotificationBackend implements HttpClientAdapter {
  final List<Map<String, dynamic>> notifications = [
    {
      'id': 1,
      'user_id': 3,
      'type': 'candidate_added',
      'is_read': false,
      'created_at': '2026-01-01T00:00:00Z',
    },
    {
      'id': 2,
      'user_id': 3,
      'type': 'task_created',
      'is_read': false,
      'created_at': '2026-01-01T00:01:00Z',
    },
  ];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final data = _handle(options);
    return ResponseBody.fromBytes(
      Uint8List.fromList(utf8.encode(jsonEncode(data))),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  Map<String, dynamic> _handle(RequestOptions options) {
    if (options.method == 'GET' && options.path == '/api/notifications') {
      return {'notifications': notifications, 'total': notifications.length};
    }
    if (options.method == 'GET' &&
        options.path == '/api/notifications/unread-count') {
      final count = notifications.where((n) => n['is_read'] == false).length;
      return {'count': count};
    }
    if (options.method == 'POST' &&
        RegExp(r'^/api/notifications/\d+/read$').hasMatch(options.path)) {
      final id = int.parse(options.path.split('/')[3]);
      final n = notifications.firstWhere((n) => n['id'] == id);
      n['is_read'] = true;
      return {'notification': n};
    }
    if (options.method == 'POST' &&
        options.path == '/api/notifications/read-all') {
      for (final n in notifications) {
        n['is_read'] = true;
      }
      return {'message': 'all notifications marked read'};
    }
    throw StateError('unhandled fake route: ${options.method} ${options.path}');
  }

  @override
  void close({bool force = false}) {}
}

ProviderContainer _containerWithFakeBackend(_FakeNotificationBackend backend) {
  final client = ApiClient.test(tokenProvider: () async => 'test-token');
  client.debugDio.httpClientAdapter = backend;
  return ProviderContainer(
    overrides: [apiClientProvider.overrideWithValue(client)],
  );
}

void main() {
  test(
    'unreadNotificationCountProvider reflects the real server count',
    () async {
      final container = _containerWithFakeBackend(_FakeNotificationBackend());
      addTearDown(container.dispose);

      expect(await container.read(unreadNotificationCountProvider.future), 2);
    },
  );

  test(
    'markRead() invalidates the unread count — it drops by exactly one',
    () async {
      final container = _containerWithFakeBackend(_FakeNotificationBackend());
      addTearDown(container.dispose);

      expect(await container.read(unreadNotificationCountProvider.future), 2);

      await container.read(notificationActionsProvider).markRead(1);

      expect(await container.read(unreadNotificationCountProvider.future), 1);
    },
  );

  test('markAllRead() invalidates the unread count down to zero', () async {
    final container = _containerWithFakeBackend(_FakeNotificationBackend());
    addTearDown(container.dispose);

    await container.read(notificationActionsProvider).markAllRead();

    expect(await container.read(unreadNotificationCountProvider.future), 0);
    final (notifications, _) = await container.read(
      notificationsProvider.future,
    );
    expect(notifications.every((n) => n.isRead), isTrue);
  });
}
