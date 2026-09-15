import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/models/manager_conversation.dart';
import 'package:mereytoi_app/models/manager_message.dart';

void main() {
  group('ManagerConversation.fromJson', () {
    test('a general conversation (no event/listing context)', () {
      final conv = ManagerConversation.fromJson({
        'id': 1,
        'user_id': 3,
        'status': 'open',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      });
      expect(conv.eventId, isNull);
      expect(conv.listingId, isNull);
      expect(conv.status, 'open');
    });

    test(
      'a listing-scoped conversation with a nested listing (respondDetail Preloads it)',
      () {
        final conv = ManagerConversation.fromJson({
          'id': 2,
          'user_id': 3,
          'listing_id': 5,
          'listing': {
            'id': 5,
            'category_id': 1,
            'name_ru': 'Ведущий',
            'name_kz': 'Ведущий',
            'description_ru': '',
            'description_kz': '',
            'city': '',
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
          'status': 'open',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        });
        expect(conv.listingId, 5);
        expect(conv.listing?.nameRu, 'Ведущий');
      },
    );
  });

  group('ManagerMessage.fromJson', () {
    test('a message from the customer', () {
      final msg = ManagerMessage.fromJson({
        'id': 1,
        'conversation_id': 2,
        'sender_type': 'user',
        'sender_user_id': 3,
        'body': 'Здравствуйте!',
        'created_at': '2026-01-01T00:00:00Z',
      });
      expect(msg.isFromManager, isFalse);
      expect(msg.body, 'Здравствуйте!');
      expect(msg.readAt, isNull);
    });

    test('a message from the manager, already read', () {
      final msg = ManagerMessage.fromJson({
        'id': 2,
        'conversation_id': 2,
        'sender_type': 'manager',
        'body': 'Добрый день! Чем можем помочь?',
        'read_at': '2026-01-01T01:00:00Z',
        'created_at': '2026-01-01T00:30:00Z',
      });
      expect(msg.isFromManager, isTrue);
      expect(msg.readAt, isNotNull);
    });
  });
}
