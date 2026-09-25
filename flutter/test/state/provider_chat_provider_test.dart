import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/network/api_client.dart';
import 'package:mereytoi_app/state/provider_chat_provider.dart';
import 'package:mereytoi_app/state/providers.dart';

/// Records every request path/method it sees, then answers with a minimal
/// but valid conversation+messages shape regardless of which endpoint was
/// hit — the assertions below are about *which* endpoint the notifier
/// chose, not about parsing correctness (already covered by
/// provider_chat_model_parsing_test.dart).
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
        'id': 1,
        'provider_id': 2,
        'customer_user_id': 3,
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
  // Regression test for the Этап 11G device-QA finding: a provider opening
  // an *existing* conversation from ProviderChatListScreen must never call
  // POST /api/provider-chat/start — that endpoint's own find-or-create
  // query is customer-only (`WHERE customer_user_id = caller`), so a
  // provider calling it to reopen their own inbox item searches for a
  // conversation where *they* are the customer (never true) and the
  // backend's self-chat guard then rejects it with 400 "cannot message
  // your own provider profile" — even though the provider isn't starting a
  // self-chat, they're just trying to read a real conversation they're
  // already a legitimate participant of.
  test(
    'a known conversationId fetches directly via GET, never via POST /start',
    () async {
      final backend = _RecordingBackend();
      final container = _containerWithBackend(backend);
      addTearDown(container.dispose);

      const key = (providerId: 2, listingId: null, conversationId: 1);
      // Force the provider to build/load by reading its current state.
      container.read(providerChatProvider(key));
      // The notifier's constructor kicks off `_load()` asynchronously;
      // pump the event queue until the fake HTTP round-trip completes.
      await pumpEventQueue();

      expect(backend.requests, hasLength(1));
      expect(backend.requests.single, ('GET', '/api/provider-chat/1'));
    },
  );

  test(
    'no conversationId (customer opening from a service page) uses POST /start',
    () async {
      final backend = _RecordingBackend();
      final container = _containerWithBackend(backend);
      addTearDown(container.dispose);

      const key = (providerId: 2, listingId: 5, conversationId: null);
      container.read(providerChatProvider(key));
      await pumpEventQueue();

      expect(backend.requests, hasLength(1));
      expect(backend.requests.single, ('POST', '/api/provider-chat/start'));
    },
  );
}
