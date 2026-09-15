import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/network/api_client.dart';
import 'package:mereytoi_app/services/event_service.dart';

/// A fake transport that routes on "METHOD path" and hands back canned
/// JSON — same seam `test/core/api_client_interceptor_test.dart` already
/// uses (`ApiClient.test` + a fake `HttpClientAdapter`), extended here with
/// a per-call responder so one adapter can cover a whole endpoint map
/// without a real network call or platform channel.
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
    // utf8.encode, not `.codeUnits` — the latter is UTF-16 code units, which
    // silently corrupts any non-ASCII text (this response carries RU
    // Cyrillic), producing invalid UTF-8 bytes downstream.
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

(EventService, _FakeAdapter) _service(
  Map<String, dynamic> Function(RequestOptions options) responder,
) {
  final adapter = _FakeAdapter(responder);
  final client = ApiClient.test(tokenProvider: () async => 'test-token');
  client.debugDio.httpClientAdapter = adapter;
  return (EventService(client), adapter);
}

void main() {
  group('addCandidate', () {
    test(
      'an ordinary service sends only listing_id — no hall/menu/guests/estimated_total',
      () async {
        final (service, adapter) = _service((options) {
          return {
            'candidate': {
              'id': 1,
              'event_id': 7,
              'listing_id': 5,
              'status': 'shortlisted',
              'added_by_id': 3,
              'created_at': '2026-01-01T00:00:00Z',
              'updated_at': '2026-01-01T00:00:00Z',
            },
            'already_added': false,
          };
        });

        final (candidate, alreadyAdded) = await service.addCandidate(
          eventId: 7,
          listingId: 5,
        );

        final sentBody = adapter.requests.single.data as Map;
        expect(sentBody['listing_id'], 5);
        expect(sentBody['hall_id'], isNull);
        expect(sentBody['menu_id'], isNull);
        expect(candidate.id, 1);
        expect(alreadyAdded, isFalse);
      },
    );

    test(
      'a restaurant variant preserves hall/menu/guests/estimated_total through the round trip',
      () async {
        final (service, adapter) = _service((options) {
          final body = options.data as Map;
          return {
            'candidate': {
              'id': 2,
              'event_id': 7,
              'listing_id': 42,
              'hall_id': body['hall_id'],
              'menu_id': body['menu_id'],
              'hall_name': 'Sultan Hall',
              'menu_name': 'Банкетное меню №1',
              'menu_price_per_guest': 25000,
              'guests': body['guests'],
              'estimated_total': body['estimated_total'],
              'status': 'shortlisted',
              'added_by_id': 3,
              'created_at': '2026-01-01T00:00:00Z',
              'updated_at': '2026-01-01T00:00:00Z',
            },
            'already_added': false,
          };
        });

        final (candidate, alreadyAdded) = await service.addCandidate(
          eventId: 7,
          listingId: 42,
          hallId: 1,
          menuId: 2,
          guests: 150,
          estimatedTotal: 3850000,
        );

        final sentBody = adapter.requests.single.data as Map;
        expect(sentBody['hall_id'], 1);
        expect(sentBody['menu_id'], 2);
        expect(sentBody['guests'], 150);
        expect(sentBody['estimated_total'], 3850000);

        expect(candidate.hallId, 1);
        expect(candidate.hallName, 'Sultan Hall');
        expect(candidate.menuId, 2);
        expect(candidate.menuName, 'Банкетное меню №1');
        expect(candidate.guests, 150);
        expect(candidate.estimatedTotal, 3850000);
        expect(alreadyAdded, isFalse);
      },
    );

    test('re-adding the same variant surfaces already_added: true', () async {
      final (service, _) = _service((options) {
        return {
          'candidate': {
            'id': 2,
            'event_id': 7,
            'listing_id': 42,
            'status': 'shortlisted',
            'added_by_id': 3,
            'created_at': '2026-01-01T00:00:00Z',
            'updated_at': '2026-01-01T00:00:00Z',
          },
          'already_added': true,
        };
      });

      final (_, alreadyAdded) = await service.addCandidate(
        eventId: 7,
        listingId: 42,
        hallId: 1,
        menuId: 2,
      );
      expect(alreadyAdded, isTrue);
    });
  });

  test(
    'updateCandidateStatus sends {status} and parses the updated candidate',
    () async {
      final (service, adapter) = _service((options) {
        expect(options.method, 'PUT');
        expect(options.path, '/api/events/7/candidates/2');
        return {
          'candidate': {
            'id': 2,
            'event_id': 7,
            'listing_id': 42,
            'status': (options.data as Map)['status'],
            'added_by_id': 3,
            'created_at': '2026-01-01T00:00:00Z',
            'updated_at': '2026-01-01T00:00:00Z',
          },
        };
      });

      final candidate = await service.updateCandidateStatus(
        eventId: 7,
        candidateId: 2,
        status: 'selected',
      );
      expect(candidate.status, 'selected');
      expect((adapter.requests.single.data as Map)['status'], 'selected');
    },
  );

  test('vote posts {value} to the right path and parses the vote', () async {
    final (service, adapter) = _service((options) {
      expect(options.path, '/api/events/7/candidates/2/vote');
      return {
        'vote': {
          'id': 9,
          'candidate_id': 2,
          'user_id': 3,
          'value': (options.data as Map)['value'],
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        },
      };
    });

    final vote = await service.vote(eventId: 7, candidateId: 2, value: 'up');
    expect(vote.value, 'up');
    expect((adapter.requests.single.data as Map)['value'], 'up');
  });

  test(
    'addComment sends body + candidate_id (null for general discussion)',
    () async {
      final (service, adapter) = _service((options) {
        final body = options.data as Map;
        return {
          'comment': {
            'id': 1,
            'event_id': 7,
            'candidate_id': body['candidate_id'],
            'user_id': 3,
            'body': body['body'],
            'created_at': '2026-01-01T00:00:00Z',
          },
        };
      });

      final comment = await service.addComment(
        eventId: 7,
        body: 'Привет команда',
      );
      expect(comment.body, 'Привет команда');
      expect(comment.candidateId, isNull);
      expect((adapter.requests.single.data as Map)['candidate_id'], isNull);
    },
  );

  group('tasks', () {
    test(
      'createTask sends title/assignee_id/due_date and parses the new task',
      () async {
        final (service, adapter) = _service((options) {
          final body = options.data as Map;
          return {
            'task': {
              'id': 1,
              'event_id': 7,
              'title': body['title'],
              'due_date': body['due_date'],
              'status': 'todo',
              'created_by_id': 3,
              'created_at': '2026-01-01T00:00:00Z',
              'updated_at': '2026-01-01T00:00:00Z',
            },
          };
        });

        final task = await service.createTask(
          eventId: 7,
          title: 'Забронировать зал',
          dueDate: DateTime(2027, 5, 1),
        );
        expect(task.title, 'Забронировать зал');
        expect((adapter.requests.single.data as Map)['due_date'], '2027-05-01');
      },
    );

    test(
      'updateTaskStatus sends only {status} — never title/assignee/due_date',
      () async {
        final (service, adapter) = _service((options) {
          return {
            'task': {
              'id': 1,
              'event_id': 7,
              'title': 'Забронировать зал',
              'status': (options.data as Map)['status'],
              'created_by_id': 3,
              'created_at': '2026-01-01T00:00:00Z',
              'updated_at': '2026-01-01T00:00:00Z',
            },
          };
        });

        final task = await service.updateTaskStatus(
          eventId: 7,
          taskId: 1,
          status: 'done',
        );
        expect(task.status, 'done');
        final sentBody = adapter.requests.single.data as Map;
        expect(sentBody.keys, ['status']);
      },
    );
  });

  group('event request', () {
    test(
      'submitRequest is idempotent-aware: parses already_submitted',
      () async {
        final (service, _) = _service((options) {
          expect(options.path, '/api/events/7/request/submit');
          return {
            'request': {
              'id': 1,
              'event_id': 7,
              'created_by_id': 3,
              'status': 'submitted',
              'organizer_comment': '',
              'manager_comment': '',
              'latest_revision': 1,
              'created_at': '2026-01-01T00:00:00Z',
              'updated_at': '2026-01-01T00:00:00Z',
            },
            'already_submitted': true,
          };
        });

        final (request, alreadySubmitted) = await service.submitRequest(7);
        expect(request.status, 'submitted');
        expect(alreadySubmitted, isTrue);
      },
    );

    test(
      'cancelRequest posts to /request/cancel and parses the cancelled request',
      () async {
        final (service, adapter) = _service((options) {
          return {
            'request': {
              'id': 1,
              'event_id': 7,
              'created_by_id': 3,
              'status': 'cancelled',
              'organizer_comment': '',
              'manager_comment': '',
              'latest_revision': 0,
              'created_at': '2026-01-01T00:00:00Z',
              'updated_at': '2026-01-01T00:00:00Z',
            },
          };
        });

        final request = await service.cancelRequest(7);
        expect(request.status, 'cancelled');
        expect(adapter.requests.single.path, '/api/events/7/request/cancel');
      },
    );
  });
}
