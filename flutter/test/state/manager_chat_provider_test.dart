import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/network/api_client.dart';
import 'package:mereytoi_app/state/manager_chat_provider.dart';
import 'package:mereytoi_app/state/providers.dart';

/// Same recording fake as provider_chat_provider_test.dart — answers every
/// request with a minimal valid conversation, so the assertions are only
/// about which endpoint the notifier chose.
class _RecordingBackend implements HttpClientAdapter {
  final List<(String method, String path)> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add((options.method, options.path));
    final data = {
      'conversation': {
        'id': 9,
        'user_id': 3,
        'status': 'closed',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      },
      'messages': <Map<String, dynamic>>[],
    };
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

ProviderContainer _containerWithBackend(_RecordingBackend backend) {
  final client = ApiClient.test(tokenProvider: () async => 'test-token');
  client.debugDio.httpClientAdapter = backend;
  return ProviderContainer(
    overrides: [apiClientProvider.overrideWithValue(client)],
  );
}

void main() {
  // Этап 12B: a manager_message_received notification opens the exact
  // thread by id. Going through POST /start instead would re-resolve by
  // (event_id, listing_id) among *open* conversations only, so a thread
  // the manager has since closed would silently open empty.
  test(
    'a known conversationId fetches directly via GET, never via POST /start',
    () async {
      final backend = _RecordingBackend();
      final container = _containerWithBackend(backend);
      addTearDown(container.dispose);

      const key = (eventId: null, listingId: 5, conversationId: 9);
      // listen (not read) keeps the autoDispose provider alive for the
      // state assertion below.
      final sub = container.listen(managerChatProvider(key), (_, _) {});
      addTearDown(sub.close);
      await pumpEventQueue();

      expect(backend.requests, hasLength(1));
      expect(backend.requests.single, ('GET', '/api/manager-chat/9'));
      expect(sub.read().value?.conversation?.id, 9);
    },
  );

  test(
    'no conversationId (context entry points) keeps using POST /start',
    () async {
      final backend = _RecordingBackend();
      final container = _containerWithBackend(backend);
      addTearDown(container.dispose);

      const key = (eventId: null, listingId: 5, conversationId: null);
      container.read(managerChatProvider(key));
      await pumpEventQueue();

      expect(backend.requests, hasLength(1));
      expect(backend.requests.single, ('POST', '/api/manager-chat/start'));
    },
  );
}
