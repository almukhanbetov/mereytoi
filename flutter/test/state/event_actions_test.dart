import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/network/api_client.dart';
import 'package:mereytoi_app/state/event_actions.dart';
import 'package:mereytoi_app/state/event_providers.dart';
import 'package:mereytoi_app/state/providers.dart';

/// A stateful fake backend: routes on "METHOD path" and can react to
/// writes (e.g. `addCandidate` actually grows what the next `List` call
/// returns) — enough to test that `EventActions` invalidates exactly the
/// providers that should refetch after a mutation, using real (not
/// hand-waved) request/response round trips.
class _FakeEventBackend implements HttpClientAdapter {
  final List<Map<String, dynamic>> events = [];
  final List<Map<String, dynamic>> candidates = [];
  int _nextId = 1;

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
    final path = options.path;
    final method = options.method;

    if (method == 'GET' && path == '/api/events') {
      return {'events': events};
    }
    if (method == 'POST' && path == '/api/events') {
      final body = options.data as Map;
      final event = {
        'id': _nextId++,
        'owner_id': 1,
        'title': body['title'],
        'type': body['type'],
        'city': body['city'],
        'guests': body['guests'],
        'budget_total': body['budget_total'],
        'comment': body['comment'],
        'status': 'planning',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
        'my_role': 'owner',
      };
      events.add(event);
      return {'event': event};
    }
    if (method == 'GET' &&
        RegExp(r'^/api/events/\d+/candidates$').hasMatch(path)) {
      return {'candidates': candidates};
    }
    if (method == 'POST' &&
        RegExp(r'^/api/events/\d+/candidates$').hasMatch(path)) {
      final body = options.data as Map;
      final candidate = {
        'id': _nextId++,
        'event_id': 1,
        'listing_id': body['listing_id'],
        'status': 'shortlisted',
        'added_by_id': 1,
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      };
      candidates.add(candidate);
      return {'candidate': candidate, 'already_added': false};
    }
    if (method == 'PUT' &&
        RegExp(r'^/api/events/\d+/candidates/\d+$').hasMatch(path)) {
      final body = options.data as Map;
      final id = int.parse(path.split('/').last);
      final candidate = candidates.firstWhere((c) => c['id'] == id);
      candidate['status'] = body['status'];
      return {'candidate': candidate};
    }
    throw StateError('unhandled fake route: $method $path');
  }

  @override
  void close({bool force = false}) {}
}

ProviderContainer _containerWithFakeBackend(_FakeEventBackend backend) {
  final client = ApiClient.test(tokenProvider: () async => 'test-token');
  client.debugDio.httpClientAdapter = backend;
  final container = ProviderContainer(
    overrides: [apiClientProvider.overrideWithValue(client)],
  );
  return container;
}

void main() {
  test(
    'an empty events list renders as an empty (not error/null) list',
    () async {
      final backend = _FakeEventBackend();
      final container = _containerWithFakeBackend(backend);
      addTearDown(container.dispose);

      final events = await container.read(eventsProvider.future);
      expect(events, isEmpty);
    },
  );

  test(
    'createEvent invalidates eventsProvider — the new event shows up without a manual refetch call',
    () async {
      final backend = _FakeEventBackend();
      final container = _containerWithFakeBackend(backend);
      addTearDown(container.dispose);

      final before = await container.read(eventsProvider.future);
      expect(before, isEmpty);

      await container
          .read(eventActionsProvider)
          .createEvent(
            title: 'Свадьба',
            type: 'wedding',
            city: 'Алматы',
            guests: 100,
            budgetTotal: 5000000,
            comment: '',
          );

      final after = await container.read(eventsProvider.future);
      expect(after, hasLength(1));
      expect(after.single.title, 'Свадьба');
    },
  );

  test(
    'an event with zero candidates renders as an empty (not error/null) list',
    () async {
      final backend = _FakeEventBackend();
      final container = _containerWithFakeBackend(backend);
      addTearDown(container.dispose);

      final candidates = await container.read(
        eventCandidatesProvider(1).future,
      );
      expect(candidates, isEmpty);
    },
  );

  test(
    'addCandidate invalidates eventCandidatesProvider for that event',
    () async {
      final backend = _FakeEventBackend();
      final container = _containerWithFakeBackend(backend);
      addTearDown(container.dispose);

      final before = await container.read(eventCandidatesProvider(1).future);
      expect(before, isEmpty);

      await container
          .read(eventActionsProvider)
          .addCandidate(eventId: 1, listingId: 5);

      final after = await container.read(eventCandidatesProvider(1).future);
      expect(after, hasLength(1));
      expect(after.single.listingId, 5);
    },
  );

  test(
    'updateCandidateStatus invalidates eventCandidatesProvider with the new status visible',
    () async {
      final backend = _FakeEventBackend();
      final container = _containerWithFakeBackend(backend);
      addTearDown(container.dispose);

      final (candidate, _) = await container
          .read(eventActionsProvider)
          .addCandidate(eventId: 1, listingId: 5);

      await container
          .read(eventActionsProvider)
          .updateCandidateStatus(
            eventId: 1,
            candidateId: candidate.id,
            status: 'selected',
          );

      final after = await container.read(eventCandidatesProvider(1).future);
      expect(after.single.status, 'selected');
    },
  );
}
