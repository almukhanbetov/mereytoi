import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/models/app_notification.dart';

void main() {
  group('AppNotification.fromJson', () {
    test('an unread candidate_added notification with a deep-link target', () {
      final n = AppNotification.fromJson({
        'id': 1,
        'user_id': 3,
        'actor_id': 4,
        'event_id': 7,
        'type': 'candidate_added',
        'entity_type': 'candidate',
        'entity_id': 12,
        'payload': {'name': 'Ведущий', 'price': 250000},
        'is_read': false,
        'created_at': '2026-01-01T00:00:00Z',
      });

      expect(n.type, 'candidate_added');
      expect(n.entityType, 'candidate');
      expect(n.entityId, 12);
      expect(n.payload['name'], 'Ведущий');
      expect(n.isRead, isFalse);
      expect(n.readAt, isNull);
    });

    test(
      'a read notification with entity_type/entity_id absent (e.g. budget_updated)',
      () {
        final n = AppNotification.fromJson({
          'id': 2,
          'user_id': 3,
          'event_id': 7,
          'type': 'budget_updated',
          'payload': {'budget_total': 5000000},
          'is_read': true,
          'read_at': '2026-01-02T00:00:00Z',
          'created_at': '2026-01-01T00:00:00Z',
        });

        expect(n.entityType, isNull);
        expect(n.entityId, isNull);
        expect(n.isRead, isTrue);
        expect(n.readAt, isNotNull);
      },
    );

    test('a system-generated notification has no actor', () {
      final n = AppNotification.fromJson({
        'id': 3,
        'user_id': 3,
        'type': 'workspace_created',
        'is_read': false,
        'created_at': '2026-01-01T00:00:00Z',
      });
      expect(n.actorId, isNull);
      expect(n.actor, isNull);
    });
  });
}
