import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/models/provider_profile.dart';

void main() {
  group('ProviderProfile.fromJson', () {
    test('parses GET /api/provider/me\'s response', () {
      final profile = ProviderProfile.fromJson({
        'id': 1,
        'user_id': 9,
        'display_name': 'Aigerim MC',
        'city': 'Алматы',
        'description': 'Ведущая мероприятий',
        'phone': '+77001234567',
        'whatsapp': '+77001234567',
        'telegram': '@aigerim',
        'avatar_url': '/uploads/avatar.jpg',
        'status': 'active',
      });
      expect(profile.displayName, 'Aigerim MC');
      expect(profile.status, 'active');
      expect(profile.telegram, '@aigerim');
    });
  });

  group('Listing — Этап 11 additions', () {
    test('price_type and provider brief parse off the catalog/detail shape', () {
      final listing = Listing.fromJson({
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
        'emoji': '✨',
        'color_from': '#3a1420',
        'color_to': '#d4af6a',
        'image_urls': [],
        'is_active': true,
        'price_type': 'per_event',
        'provider': {
          'display_name': 'Aigerim MC',
          'city': 'Алматы',
          'avatar_url': '/uploads/avatar.jpg',
        },
      });
      expect(listing.priceType, 'per_event');
      expect(listing.provider, isNotNull);
      expect(listing.provider!.displayName, 'Aigerim MC');
    });

    test('a pre-existing listing with neither field simply has them null — no crash', () {
      final listing = Listing.fromJson({
        'id': 1,
        'category_id': 1,
        'name_ru': 'Aurora Quintet',
        'name_kz': 'Aurora Quintet',
        'description_ru': '',
        'description_kz': '',
        'city': '',
        'phone': '',
        'price': 80000,
        'min_guests': 0,
        'max_guests': 0,
        'rating': 0,
        'emoji': '',
        'color_from': '',
        'color_to': '',
        'image_urls': [],
        'is_active': true,
      });
      expect(listing.priceType, isNull);
      expect(listing.provider, isNull);
    });
  });
}
