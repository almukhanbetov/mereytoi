import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/models/booking.dart';
import 'package:mereytoi_app/models/category.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/models/site_statistics.dart';
import 'package:mereytoi_app/state/locale_provider.dart';

void main() {
  group('Category.fromJson', () {
    test('parses a real GET /api/categories row', () {
      final category = Category.fromJson({
        'id': 2,
        'slug': 'hosts',
        'name_ru': 'Ведущие',
        'name_kz': 'Жүргізушілер',
        'position': 1,
        'image_url': '/uploads/hosts.jpg',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      });

      expect(category.id, 2);
      expect(category.slug, 'hosts');
      expect(category.name(AppLocale.ru), 'Ведущие');
      expect(category.name(AppLocale.kz), 'Жүргізушілер');
      expect(category.imageUrl, '/uploads/hosts.jpg');
    });

    test('nullable image_url (category with no photo) parses without throwing', () {
      final category = Category.fromJson({
        'id': 3,
        'slug': 'venues',
        'name_ru': 'Рестораны и локации',
        'name_kz': 'Мейрамханалар',
        'position': 0,
      });
      expect(category.imageUrl, isNull);
    });
  });

  group('Listing.fromJson', () {
    test('parses a real GET /api/listings row (no nested category — list endpoint omits it)', () {
      final listing = Listing.fromJson({
        'id': 5,
        'category_id': 2,
        'name_ru': 'Динара Касымова',
        'name_kz': 'Динара Касымова',
        'description_ru': 'Ведущая на двух языках',
        'description_kz': '',
        'city': 'Алматы',
        'phone': '+7 700 123 45 67',
        'price': 250000,
        'min_guests': 0,
        'max_guests': 0,
        'rating': 4.8,
        'emoji': '🎤',
        'color_from': '#111',
        'color_to': '#222',
        'image_urls': ['/uploads/a.jpg', '/uploads/b.jpg'],
        'video_urls': [],
        'is_active': true,
      });

      expect(listing.id, 5);
      expect(listing.name(AppLocale.ru), 'Динара Касымова');
      expect(listing.price, 250000);
      expect(listing.rating, 4.8);
      expect(listing.imageUrls, ['/uploads/a.jpg', '/uploads/b.jpg']);
      expect(listing.coverImage, '/uploads/a.jpg');
      expect(listing.category, isNull);
      expect(listing.isPerPerson, isFalse);
    });

    test('parses the detail endpoint shape, which nests category via GORM Preload', () {
      final listing = Listing.fromJson({
        'id': 9,
        'category_id': 1,
        'category': {'id': 1, 'slug': 'venues', 'name_ru': 'Рестораны', 'name_kz': 'Мейрамхана', 'position': 0},
        'name_ru': 'Almaty Grand Hall',
        'name_kz': 'Almaty Grand Hall',
        'description_ru': '',
        'description_kz': '',
        'city': 'Алматы',
        'phone': '',
        'price': 12000,
        'min_guests': 50,
        'max_guests': 500,
        'rating': 4.8,
        'emoji': '',
        'color_from': '',
        'color_to': '',
        'image_urls': [],
        'video_urls': [],
        'is_active': true,
      });

      expect(listing.category?.slug, 'venues');
      expect(listing.isPerPerson, isTrue); // min_guests>0 && max_guests>min_guests
      expect(listing.coverImage, isNull); // empty image_urls
    });
  });

  group('SiteStatistics.fromJson', () {
    test('parses GET /api/site-statistics — plain integers, no "+" baked in', () {
      final stats = SiteStatistics.fromJson({
        'events_count': 250,
        'happy_guests_count': 15000,
        'years_experience': 8,
        'cities_count': 5,
      });
      expect(stats.eventsCount, 250);
      expect(stats.happyGuestsCount, 15000);
      expect(stats.yearsExperience, 8);
      expect(stats.citiesCount, 5);
    });
  });

  group('Booking.fromJson', () {
    test('parses the booking object POST /api/bookings responds with', () {
      final booking = Booking.fromJson({
        'id': 42,
        'public_ref': 'abc123def456',
        'name': 'Тестовый клиент',
        'phone': '+7 700 123 45 67',
        'status': 'new',
      });
      expect(booking.id, 42);
      expect(booking.publicRef, 'abc123def456');
      expect(booking.status, 'new');
    });
  });
}
