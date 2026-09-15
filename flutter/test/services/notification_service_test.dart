import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/network/api_client.dart';
import 'package:mereytoi_app/services/notification_service.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.responder);

  final Map<String, dynamic> Function(RequestOptions options) responder;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final data = responder(options);
    final body = Uint8List.fromList(utf8.encode(jsonEncode(data)));
    return ResponseBody.fromBytes(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

(NotificationService, _FakeAdapter) _service(
  Map<String, dynamic> Function(RequestOptions options) responder,
) {
  final adapter = _FakeAdapter(responder);
  final client = ApiClient.test(tokenProvider: () async => 'test-token');
  client.debugDio.httpClientAdapter = adapter;
  return (NotificationService(client), adapter);
}

void main() {
  test(
    'list() parses (notifications, total) and defaults limit=20/page=1',
    () async {
      final (service, adapter) = _service((options) {
        expect(options.path, '/api/notifications');
        return {
          'notifications': [
            {
              'id': 1,
              'user_id': 3,
              'type': 'candidate_added',
              'is_read': false,
              'created_at': '2026-01-01T00:00:00Z',
            },
          ],
          'total': 5,
          'page': 1,
          'limit': 20,
        };
      });

      final (notifications, total) = await service.list();
      expect(notifications, hasLength(1));
      expect(total, 5);
      expect(adapter.requests.single.queryParameters['limit'], 20);
      expect(adapter.requests.single.queryParameters['page'], 1);
      expect(
        adapter.requests.single.queryParameters.containsKey('unread'),
        isFalse,
      );
    },
  );

  test('list(unreadOnly: true) sends ?unread=true', () async {
    final (service, adapter) = _service((options) {
      return {'notifications': [], 'total': 0};
    });
    await service.list(unreadOnly: true);
    expect(adapter.requests.single.queryParameters['unread'], 'true');
  });

  test('unreadCount() parses the real server count', () async {
    final (service, _) = _service((options) {
      expect(options.path, '/api/notifications/unread-count');
      return {'count': 3};
    });
    expect(await service.unreadCount(), 3);
  });

  test(
    'markRead() posts to the right id and returns the updated (now-read) notification',
    () async {
      final (service, adapter) = _service((options) {
        expect(options.path, '/api/notifications/12/read');
        return {
          'notification': {
            'id': 12,
            'user_id': 3,
            'type': 'task_created',
            'is_read': true,
            'read_at': '2026-01-01T00:05:00Z',
            'created_at': '2026-01-01T00:00:00Z',
          },
        };
      });

      final n = await service.markRead(12);
      expect(n.isRead, isTrue);
      expect(adapter.requests.single.path, '/api/notifications/12/read');
    },
  );

  test('markAllRead() posts to /read-all', () async {
    final (service, adapter) = _service((options) {
      return {'message': 'all notifications marked read'};
    });
    await service.markAllRead();
    expect(adapter.requests.single.path, '/api/notifications/read-all');
  });
}
