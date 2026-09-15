import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/domain/notification/notification_type.dart';

void main() {
  group('resolveNotificationTarget — real entity_type/type values only', () {
    test('entity_type "candidate" opens the Услуги tab (index 1)', () {
      final target = resolveNotificationTarget(
        type: notifCandidateAdded,
        entityType: 'candidate',
        eventId: 7,
      );
      expect(target, (eventId: 7, tabIndex: 1));
    });

    test('entity_type "discussion" opens the Обсуждение tab (index 3)', () {
      final target = resolveNotificationTarget(
        type: notifCommentAdded,
        entityType: 'discussion',
        eventId: 7,
      );
      expect(target, (eventId: 7, tabIndex: 3));
    });

    test('entity_type "task" opens the Задачи tab (index 4)', () {
      final target = resolveNotificationTarget(
        type: notifTaskCreated,
        entityType: 'task',
        eventId: 7,
      );
      expect(target, (eventId: 7, tabIndex: 4));
    });

    test('entity_type "member" opens the Участники tab (index 5)', () {
      final target = resolveNotificationTarget(
        type: notifMemberJoined,
        entityType: 'member',
        eventId: 7,
      );
      expect(target, (eventId: 7, tabIndex: 5));
    });

    test(
      'a request_* type with entity_type "request" opens Обзор (index 0)',
      () {
        final target = resolveNotificationTarget(
          type: notifRequestApproved,
          entityType: 'request',
          eventId: 7,
        );
        expect(target, (eventId: 7, tabIndex: 0));
      },
    );

    test(
      'request_* types resolve to Обзор even without entity_type (defensive fallback)',
      () {
        final target = resolveNotificationTarget(
          type: notifRequestSubmitted,
          entityType: null,
          eventId: 7,
        );
        expect(target, (eventId: 7, tabIndex: 0));
      },
    );

    test('budget_updated (entity_type "event") opens Обзор', () {
      final target = resolveNotificationTarget(
        type: notifBudgetUpdated,
        entityType: 'event',
        eventId: 7,
      );
      expect(target, (eventId: 7, tabIndex: 0));
    });

    test(
      'no event_id at all — never navigates anywhere, regardless of type',
      () {
        final target = resolveNotificationTarget(
          type: notifCandidateAdded,
          entityType: 'candidate',
          eventId: null,
        );
        expect(target, isNull);
      },
    );

    test(
      'an unrecognized entity_type/type combination resolves to null (no dead link guess)',
      () {
        final target = resolveNotificationTarget(
          type: 'something_new',
          entityType: 'something_else',
          eventId: 7,
        );
        expect(target, isNull);
      },
    );
  });
}
