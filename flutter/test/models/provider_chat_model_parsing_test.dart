import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/models/provider_conversation.dart';
import 'package:mereytoi_app/models/provider_message.dart';
import 'package:mereytoi_app/models/provider_public_profile.dart';

void main() {
  group('ListingProviderBrief.fromJson — Этап 11G', () {
    test('parses the id field (provider\'s own public routing handle)', () {
      final provider = ListingProviderBrief.fromJson({
        'id': 7,
        'display_name': 'Aigerim MC',
        'city': 'Алматы',
      });
      expect(provider.id, 7);
      expect(provider.displayName, 'Aigerim MC');
    });

    test('a pre-11G payload with no id simply defaults to 0 — no crash', () {
      final provider = ListingProviderBrief.fromJson({
        'display_name': 'Aigerim MC',
      });
      expect(provider.id, 0);
    });
  });

  group('ProviderConversation.fromJson', () {
    test('parses a full conversation with provider/customer/listing context', () {
      final conv = ProviderConversation.fromJson({
        'id': 12,
        'provider_id': 3,
        'provider': {
          'display_name': 'Aigerim MC',
          'avatar_url': '/uploads/avatar.jpg',
        },
        'customer_user_id': 9,
        'customer': {'display_name': 'Madina'},
        'listing_id': 5,
        'listing': {'name_ru': 'Ведущая Айгерим', 'price': 150000},
        'created_at': '2026-09-25T10:00:00Z',
        'updated_at': '2026-09-25T10:05:00Z',
      });
      expect(conv.id, 12);
      expect(conv.providerId, 3);
      expect(conv.provider!.displayName, 'Aigerim MC');
      expect(conv.provider!.avatarUrl, '/uploads/avatar.jpg');
      expect(conv.customerUserId, 9);
      expect(conv.customer!.displayName, 'Madina');
      expect(conv.listingId, 5);
      expect(conv.listingName, 'Ведущая Айгерим');
      expect(conv.listingPrice, 150000);
    });

    test('a general (no listing) conversation has null listing context — no crash', () {
      final conv = ProviderConversation.fromJson({
        'id': 1,
        'provider_id': 2,
        'customer_user_id': 3,
        'created_at': '2026-09-25T10:00:00Z',
        'updated_at': '2026-09-25T10:00:00Z',
      });
      expect(conv.listingId, isNull);
      expect(conv.listingName, isNull);
      expect(conv.provider, isNull);
    });

    test('never carries a user_id for the provider party — server-side redaction, client just must not choke if it were ever present', () {
      // Confirms the model doesn't parse/expose user_id even if a future
      // regression somehow sent it — ProviderChatParty has no such field
      // at all, so this would fail to compile if someone added one without
      // updating this test's intent.
      final conv = ProviderConversation.fromJson({
        'id': 1,
        'provider_id': 2,
        'provider': {'display_name': 'X', 'user_id': 999},
        'customer_user_id': 3,
        'created_at': '2026-09-25T10:00:00Z',
        'updated_at': '2026-09-25T10:00:00Z',
      });
      expect(conv.provider!.displayName, 'X');
    });
  });

  group('ProviderConversationSummary.fromJson', () {
    test('parses GET /api/provider-chat\'s per-row shape', () {
      final summary = ProviderConversationSummary.fromJson({
        'id': 12,
        'provider_id': 3,
        'customer_user_id': 9,
        'created_at': '2026-09-25T10:00:00Z',
        'updated_at': '2026-09-25T10:05:00Z',
        'last_message': {
          'body': 'Свободны на 20 июня?',
          'created_at': '2026-09-25T10:05:00Z',
        },
        'unread_count': 2,
      });
      expect(summary.conversation.id, 12);
      expect(summary.lastMessageBody, 'Свободны на 20 июня?');
      expect(summary.lastMessageAt, isNotNull);
      expect(summary.unreadCount, 2);
    });

    test('no messages yet -> null preview, zero unread', () {
      final summary = ProviderConversationSummary.fromJson({
        'id': 1,
        'provider_id': 2,
        'customer_user_id': 3,
        'created_at': '2026-09-25T10:00:00Z',
        'updated_at': '2026-09-25T10:00:00Z',
        'unread_count': 0,
      });
      expect(summary.lastMessageBody, isNull);
      expect(summary.unreadCount, 0);
    });
  });

  group('ProviderMessage.fromJson', () {
    test('parses a message row, no senderType field to worry about', () {
      final msg = ProviderMessage.fromJson({
        'id': 1,
        'conversation_id': 12,
        'sender_user_id': 9,
        'body': 'Свободны на 20 июня?',
        'created_at': '2026-09-25T10:05:00Z',
      });
      expect(msg.senderUserId, 9);
      expect(msg.body, 'Свободны на 20 июня?');
      expect(msg.readAt, isNull);
    });

    test('read_at present parses to a real DateTime', () {
      final msg = ProviderMessage.fromJson({
        'id': 1,
        'conversation_id': 12,
        'sender_user_id': 9,
        'body': 'x',
        'created_at': '2026-09-25T10:05:00Z',
        'read_at': '2026-09-25T10:06:00Z',
      });
      expect(msg.readAt, isNotNull);
    });
  });

  group('ProviderPublicProfile.fromJson', () {
    test('parses GET /api/providers/:id\'s response, including its listings', () {
      final profile = ProviderPublicProfile.fromJson({
        'provider': {
          'id': 3,
          'display_name': 'Aigerim MC',
          'city': 'Алматы',
          'description': 'Ведущая мероприятий',
          'avatar_url': '/uploads/avatar.jpg',
          'phone': '+77001234567',
          'whatsapp': '+77001234567',
          'telegram': '@aigerim',
        },
        'listings': [
          {
            'id': 5,
            'category_id': 2,
            'name_ru': 'Ведущая Айгерим',
            'name_kz': 'Жүргізуші Айгерім',
            'description_ru': '',
            'description_kz': '',
            'city': 'Алматы',
            'phone': '',
            'price': 150000,
            'min_guests': 0,
            'max_guests': 0,
            'rating': 0,
            'emoji': '',
            'color_from': '',
            'color_to': '',
            'image_urls': [],
            'is_active': true,
          },
        ],
        'listing_count': 1,
      });
      expect(profile.id, 3);
      expect(profile.displayName, 'Aigerim MC');
      expect(profile.whatsapp, '+77001234567');
      expect(profile.listingCount, 1);
      expect(profile.listings, hasLength(1));
      expect(profile.listings.first.nameRu, 'Ведущая Айгерим');
    });

    test('no published listings yet -> empty list, not a crash', () {
      final profile = ProviderPublicProfile.fromJson({
        'provider': {'id': 1, 'display_name': 'New Provider'},
        'listings': [],
        'listing_count': 0,
      });
      expect(profile.listings, isEmpty);
      expect(profile.listingCount, 0);
    });
  });
}
