import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/network/api_client.dart';
import 'package:mereytoi_app/services/manager_chat_service.dart';

/// Same fake-adapter seam `test/services/event_service_test.dart` already
/// established (`ApiClient.test` + a routing `HttpClientAdapter`).
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

(ManagerChatService, _FakeAdapter) _service(
  Map<String, dynamic> Function(RequestOptions options) responder,
) {
  final adapter = _FakeAdapter(responder);
  final client = ApiClient.test(tokenProvider: () async => 'test-token');
  client.debugDio.httpClientAdapter = adapter;
  return (ManagerChatService(client), adapter);
}

void main() {
  test(
    'start(): a brand-new context creates a conversation and posts the first message',
    () async {
      final (service, adapter) = _service((options) {
        expect(options.path, '/api/manager-chat/start');
        final body = options.data as Map;
        return {
          'conversation': {
            'id': 1,
            'user_id': 3,
            'event_id': body['event_id'],
            'listing_id': body['listing_id'],
            'status': 'open',
            'created_at': '2026-01-01T00:00:00Z',
            'updated_at': '2026-01-01T00:00:00Z',
          },
          'messages': [
            {
              'id': 1,
              'conversation_id': 1,
              'sender_type': 'user',
              'sender_user_id': 3,
              'body': body['message'],
              'created_at': '2026-01-01T00:00:00Z',
            },
          ],
        };
      });

      final (conversation, messages) = await service.start(
        message: 'Здравствуйте',
        listingId: 5,
      );
      expect(conversation?.listingId, 5);
      expect(messages, hasLength(1));
      expect(messages.single.body, 'Здравствуйте');
    },
  );

  test(
    'start(): re-opening the same context with an empty message just peeks (reuse, no duplicate)',
    () async {
      final (service, adapter) = _service((options) {
        final body = options.data as Map;
        // Mirrors the backend's own idempotent "peek" behavior for a
        // context that already has an open conversation.
        return {
          'conversation': {
            'id': 1,
            'user_id': 3,
            'listing_id': body['listing_id'],
            'status': 'open',
            'created_at': '2026-01-01T00:00:00Z',
            'updated_at': '2026-01-01T00:00:00Z',
          },
          'messages': [
            {
              'id': 1,
              'conversation_id': 1,
              'sender_type': 'user',
              'body': 'Здравствуйте',
              'created_at': '2026-01-01T00:00:00Z',
            },
          ],
        };
      });

      final (conversation, messages) = await service.start(listingId: 5);
      expect(conversation?.id, 1);
      expect(messages, hasLength(1));
      expect((adapter.requests.single.data as Map)['message'], '');
    },
  );

  test(
    'addMessage(): posts to the right conversation and returns the updated thread',
    () async {
      final (service, adapter) = _service((options) {
        expect(options.path, '/api/manager-chat/1/messages');
        final body = options.data as Map;
        return {
          'conversation': {
            'id': 1,
            'user_id': 3,
            'status': 'open',
            'created_at': '2026-01-01T00:00:00Z',
            'updated_at': '2026-01-01T00:00:00Z',
          },
          'messages': [
            {
              'id': 1,
              'conversation_id': 1,
              'sender_type': 'user',
              'body': 'Первое сообщение',
              'created_at': '2026-01-01T00:00:00Z',
            },
            {
              'id': 2,
              'conversation_id': 1,
              'sender_type': 'user',
              'body': body['body'],
              'created_at': '2026-01-01T00:01:00Z',
            },
          ],
        };
      });

      final (_, messages) = await service.addMessage(
        conversationId: 1,
        body: 'Второе сообщение',
      );
      expect(messages, hasLength(2));
      expect(messages.last.body, 'Второе сообщение');
      expect(adapter.requests.single.path, '/api/manager-chat/1/messages');
    },
  );

  test(
    'start(): an event-scoped context (opened from the Event Workspace) sends event_id, not listing_id',
    () async {
      final (service, adapter) = _service((options) {
        final body = options.data as Map;
        return {
          'conversation': {
            'id': 3,
            'user_id': 3,
            'event_id': body['event_id'],
            'status': 'open',
            'created_at': '2026-01-01T00:00:00Z',
            'updated_at': '2026-01-01T00:00:00Z',
          },
          'messages': <Map<String, dynamic>>[],
        };
      });

      final (conversation, _) = await service.start(eventId: 7);
      expect(conversation?.eventId, 7);
      expect(conversation?.listingId, isNull);
      final sentBody = adapter.requests.single.data as Map;
      expect(sentBody['event_id'], 7);
      expect(sentBody['listing_id'], isNull);
    },
  );

  test(
    'get(): a peek with nothing yet returns a null conversation and an empty message list',
    () async {
      final (service, _) = _service((options) {
        return {'conversation': null, 'messages': []};
      });
      final (conversation, messages) = await service.get(1);
      expect(conversation, isNull);
      expect(messages, isEmpty);
    },
  );
}
