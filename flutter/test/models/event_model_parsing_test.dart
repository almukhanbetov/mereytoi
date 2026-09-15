import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/models/event.dart';
import 'package:mereytoi_app/models/event_activity.dart';
import 'package:mereytoi_app/models/event_candidate.dart';
import 'package:mereytoi_app/models/event_comment.dart';
import 'package:mereytoi_app/models/event_member.dart';
import 'package:mereytoi_app/models/event_request.dart';
import 'package:mereytoi_app/models/event_summary.dart';
import 'package:mereytoi_app/models/event_task.dart';
import 'package:mereytoi_app/models/event_vote.dart';

void main() {
  group('Event.fromJson', () {
    test(
      'parses a real GET /api/events list row (eventWithRole — my_role inline)',
      () {
        final event = Event.fromJson({
          'id': 7,
          'owner_id': 3,
          'title': 'Свадьба Айгерим и Ерлана',
          'type': 'wedding',
          'event_date': '2027-06-20T00:00:00Z',
          'city': 'Алматы',
          'guests': 150,
          'budget_total': 5000000,
          'comment': '',
          'status': 'planning',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
          'my_role': 'owner',
        });

        expect(event.id, 7);
        expect(event.title, 'Свадьба Айгерим и Ерлана');
        expect(event.type, 'wedding');
        expect(event.eventDate, isNotNull);
        expect(event.guests, 150);
        expect(event.budgetTotal, 5000000);
        expect(event.status, 'planning');
        expect(event.myRole, 'owner');
      },
    );

    test('event_date absent (never set) parses as null, not a crash', () {
      final event = Event.fromJson({
        'id': 8,
        'owner_id': 3,
        'title': 'Корпоратив',
        'type': 'corporate',
        'city': '',
        'guests': 0,
        'budget_total': 0,
        'comment': '',
        'status': 'planning',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      });
      expect(event.eventDate, isNull);
      expect(event.myRole, isNull);
    });

    test(
      'toInputJson formats event_date as plain YYYY-MM-DD, matching parseEventDate',
      () {
        final json = Event.toInputJson(
          title: 'X',
          type: 'toi',
          eventDate: DateTime(2027, 6, 5),
          city: 'Астана',
          guests: 100,
          budgetTotal: 0,
          comment: '',
        );
        expect(json['event_date'], '2027-06-05');
      },
    );
  });

  group('EventCandidate.fromJson', () {
    test(
      'parses the bare shape AddCandidate/UpdateStatus return (no votes/my_vote/comment_count keys)',
      () {
        final candidate = EventCandidate.fromJson({
          'id': 12,
          'event_id': 7,
          'listing_id': 16,
          'hall_id': 1,
          'menu_id': 2,
          'hall_name': 'Sultan Hall',
          'menu_name': 'Банкетное меню №1',
          'menu_price_per_guest': 25000,
          'guests': 100,
          'estimated_total': 2650000,
          'status': 'shortlisted',
          'added_by_id': 3,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        });

        expect(candidate.hallId, 1);
        expect(candidate.menuId, 2);
        expect(candidate.hallName, 'Sultan Hall');
        expect(candidate.menuPricePerGuest, 25000);
        expect(candidate.guests, 100);
        expect(candidate.estimatedTotal, 2650000);
        expect(candidate.votes, isEmpty);
        expect(candidate.myVote, isNull);
        expect(candidate.commentCount, 0);
        expect(candidate.listing, isNull);
      },
    );

    test(
      'parses the enriched candidateOut shape List() returns (votes/my_vote/comment_count + nested listing)',
      () {
        final candidate = EventCandidate.fromJson({
          'id': 13,
          'event_id': 7,
          'listing_id': 5,
          'listing': {
            'id': 5,
            'category_id': 2,
            'name_ru': 'Ведущий',
            'name_kz': 'Ведущий',
            'description_ru': '',
            'description_kz': '',
            'city': 'Алматы',
            'phone': '',
            'price': 250000,
            'min_guests': 0,
            'max_guests': 0,
            'rating': 0,
            'emoji': '',
            'color_from': '',
            'color_to': '',
            'image_urls': [],
            'is_active': true,
          },
          'status': 'selected',
          'added_by_id': 3,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
          'votes': {'up': 3, 'maybe': 1},
          'my_vote': 'up',
          'comment_count': 4,
        });

        expect(candidate.listing?.nameRu, 'Ведущий');
        expect(candidate.hallId, isNull);
        expect(candidate.votes['up'], 3);
        expect(candidate.votes['maybe'], 1);
        expect(candidate.myVote, 'up');
        expect(candidate.commentCount, 4);
      },
    );

    test(
      'toAddCandidateJson matches addCandidateInput exactly for an ordinary service (no variant)',
      () {
        final json = EventCandidate.toAddCandidateJson(listingId: 5);
        expect(json['listing_id'], 5);
        expect(json['hall_id'], isNull);
        expect(json['menu_id'], isNull);
        expect(json['guests'], isNull);
        expect(json['estimated_total'], isNull);
      },
    );

    test('toAddCandidateJson carries the full restaurant variant snapshot', () {
      final json = EventCandidate.toAddCandidateJson(
        listingId: 42,
        hallId: 1,
        menuId: 2,
        guests: 100,
        estimatedTotal: 2650000,
      );
      expect(json['listing_id'], 42);
      expect(json['hall_id'], 1);
      expect(json['menu_id'], 2);
      expect(json['guests'], 100);
      expect(json['estimated_total'], 2650000);
    });
  });

  group('EventSummary.fromJson', () {
    test('parses GET /api/events/:id/summary, remaining can be negative', () {
      final summary = EventSummary.fromJson({
        'budget_total': 1000000,
        'spent': 1500000,
        'remaining': -500000,
        'categories_total': 6,
        'categories_covered': 2,
        'members_count': 3,
        'selected_count': 2,
        'shortlisted_count': 5,
      });
      expect(summary.remaining, -500000);
      expect(summary.categoriesCovered, 2);
      expect(summary.membersCount, 3);
    });
  });

  group('EventComment.fromJson', () {
    test('parses a general-discussion comment (candidate_id absent)', () {
      final comment = EventComment.fromJson({
        'id': 1,
        'event_id': 7,
        'user_id': 3,
        'user': {
          'id': 3,
          'name': 'Айгерим',
          'email': 'a@example.com',
          'phone': '',
          'role': 'user',
          'status': 'active',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        },
        'body': 'Всем привет!',
        'created_at': '2026-01-01T00:00:00Z',
      });
      expect(comment.candidateId, isNull);
      expect(comment.user?.name, 'Айгерим');
      expect(comment.body, 'Всем привет!');
    });
  });

  group('EventTask.fromJson', () {
    test('parses a task with an assignee and due date', () {
      final task = EventTask.fromJson({
        'id': 1,
        'event_id': 7,
        'title': 'Забронировать тамаду',
        'assignee_id': 4,
        'assignee': {
          'id': 4,
          'name': 'Ерлан',
          'email': 'e@example.com',
          'phone': '',
          'role': 'user',
          'status': 'active',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        },
        'due_date': '2027-05-01T00:00:00Z',
        'status': 'todo',
        'created_by_id': 3,
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      });
      expect(task.assignee?.name, 'Ерлан');
      expect(task.dueDate, isNotNull);
      expect(task.status, 'todo');
    });
  });

  group('EventActivity.fromJson', () {
    test(
      'payload is already-decoded (server unmarshals PayloadJSON before responding)',
      () {
        final activity = EventActivity.fromJson({
          'id': 1,
          'event_id': 7,
          'actor_id': 3,
          'verb': 'candidate.added',
          'payload': {'name': 'Ведущий', 'price': 250000},
          'created_at': '2026-01-01T00:00:00Z',
        });
        expect(activity.verb, 'candidate.added');
        expect(activity.payload['name'], 'Ведущий');
        expect(activity.payload['price'], 250000);
      },
    );

    test('actor_id absent (system-generated entry) parses fine', () {
      final activity = EventActivity.fromJson({
        'id': 2,
        'event_id': 7,
        'verb': 'event.created',
        'created_at': '2026-01-01T00:00:00Z',
      });
      expect(activity.actorId, isNull);
      expect(activity.payload, isEmpty);
    });
  });

  group('EventMember/EventInvitation.fromJson', () {
    test('member row', () {
      final member = EventMember.fromJson({
        'id': 1,
        'event_id': 7,
        'user_id': 3,
        'role': 'owner',
        'joined_at': '2026-01-01T00:00:00Z',
      });
      expect(member.role, 'owner');
    });

    test('invitation row — unused vs. used', () {
      final unused = EventInvitation.fromJson({
        'id': 1,
        'event_id': 7,
        'token': 'abc123',
        'role': 'editor',
        'created_by_id': 3,
        'revoked': false,
        'created_at': '2026-01-01T00:00:00Z',
      });
      expect(unused.isUsed, isFalse);

      final used = EventInvitation.fromJson({
        'id': 2,
        'event_id': 7,
        'token': 'def456',
        'role': 'viewer',
        'created_by_id': 3,
        'revoked': false,
        'used_by_id': 9,
        'used_at': '2026-02-01T00:00:00Z',
        'created_at': '2026-01-01T00:00:00Z',
      });
      expect(used.isUsed, isTrue);
    });
  });

  group('EventVote.fromJson', () {
    test('parses POST .../vote\'s response', () {
      final vote = EventVote.fromJson({
        'id': 1,
        'candidate_id': 12,
        'user_id': 3,
        'value': 'up',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      });
      expect(vote.value, 'up');
    });
  });

  group('EventRequest/EventRequestRevision.fromJson', () {
    test('draft request, no revisions yet', () {
      final request = EventRequest.fromJson({
        'id': 1,
        'event_id': 7,
        'created_by_id': 3,
        'status': 'draft',
        'organizer_comment': '',
        'manager_comment': '',
        'latest_revision': 0,
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      });
      expect(request.status, 'draft');
      expect(request.bookingId, isNull);
      expect(request.submittedAt, isNull);
    });

    test('submitted request with a linked booking and one revision', () {
      final request = EventRequest.fromJson({
        'id': 1,
        'event_id': 7,
        'created_by_id': 3,
        'status': 'submitted',
        'organizer_comment': 'Просьба перезвонить',
        'manager_comment': '',
        'booking_id': 55,
        'latest_revision': 1,
        'submitted_at': '2026-02-01T00:00:00Z',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-02-01T00:00:00Z',
      });
      expect(request.bookingId, 55);
      expect(request.submittedAt, isNotNull);

      final revision = EventRequestRevision.fromJson({
        'id': 1,
        'event_request_id': 1,
        'revision_number': 1,
        'submitted_by_id': 3,
        'snapshot': {'event_title': 'Свадьба', 'total': 3150000, 'items': []},
        'total': 3150000,
        'submitted_at': '2026-02-01T00:00:00Z',
        'created_at': '2026-02-01T00:00:00Z',
      });
      expect(revision.total, 3150000);
      expect(revision.snapshot['event_title'], 'Свадьба');
    });
  });
}
