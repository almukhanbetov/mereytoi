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

  group('resolveChatNotificationTarget — Этап 12B', () {
    test('manager reply opens ManagerChatScreen on that conversation', () {
      final target = resolveChatNotificationTarget(
        type: notifManagerMessageReceived,
        entityType: 'manager_conversation',
        entityId: 12,
        payload: {'body': 'Да', 'listing_id': 5, 'event_id': 7},
      );
      expect(target, isA<ManagerChatNotificationTarget>());
      final m = target as ManagerChatNotificationTarget;
      expect(m.conversationId, 12);
      expect(m.listingId, 5);
      expect(m.eventId, 7);
    });

    test('provider message carries provider/listing/sender context', () {
      final target = resolveChatNotificationTarget(
        type: notifProviderMessageReceived,
        entityType: 'provider_conversation',
        entityId: 4,
        payload: {
          'provider_id': 2,
          'listing_id': 8,
          'sender_name': 'Ерлан Events',
        },
        fallbackPeerName: 'Ерлан',
      );
      expect(target, isA<ProviderChatNotificationTarget>());
      final p = target as ProviderChatNotificationTarget;
      expect(p.conversationId, 4);
      expect(p.providerId, 2);
      expect(p.listingId, 8);
      expect(p.peerName, 'Ерлан Events');
    });

    test(
      'older provider notifications without sender_name fall back to the actor',
      () {
        final target =
            resolveChatNotificationTarget(
                  type: notifProviderMessageReceived,
                  entityType: 'provider_conversation',
                  entityId: 4,
                  payload: {'body': 'hi'},
                  fallbackPeerName: 'Madina',
                )
                as ProviderChatNotificationTarget;
        expect(target.peerName, 'Madina');
        expect(target.providerId, 0);
        expect(target.conversationId, 4);
      },
    );

    test('admin-side customer message has no in-app destination', () {
      expect(
        resolveChatNotificationTarget(
          type: notifManagerChatUserMessage,
          entityType: 'manager_conversation',
          entityId: 12,
        ),
        isNull,
      );
    });

    test('missing entity_id resolves to null', () {
      expect(
        resolveChatNotificationTarget(
          type: notifManagerMessageReceived,
          entityType: 'manager_conversation',
        ),
        isNull,
      );
    });

    test('event notifications are never treated as chat targets', () {
      expect(
        resolveChatNotificationTarget(
          type: notifTaskCreated,
          entityType: 'task',
          entityId: 3,
        ),
        isNull,
      );
    });
  });
}
