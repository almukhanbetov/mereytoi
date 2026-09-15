import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/models/booking.dart';
import 'package:mereytoi_app/models/category.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/models/site_statistics.dart';
import 'package:mereytoi_app/models/user.dart';
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

    test(
      'nullable image_url (category with no photo) parses without throwing',
      () {
        final category = Category.fromJson({
          'id': 3,
          'slug': 'venues',
          'name_ru': 'Рестораны и локации',
          'name_kz': 'Мейрамханалар',
          'position': 0,
        });
        expect(category.imageUrl, isNull);
      },
    );
  });

  group('Listing.fromJson', () {
    test(
      'parses a real GET /api/listings row (no nested category — list endpoint omits it)',
      () {
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
      },
    );

    test(
      'parses the detail endpoint shape, which nests category via GORM Preload',
      () {
        final listing = Listing.fromJson({
          'id': 9,
          'category_id': 1,
          'category': {
            'id': 1,
            'slug': 'venues',
            'name_ru': 'Рестораны',
            'name_kz': 'Мейрамхана',
            'position': 0,
          },
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
        expect(
          listing.isPerPerson,
          isTrue,
        ); // min_guests>0 && max_guests>min_guests
        expect(listing.coverImage, isNull); // empty image_urls
      },
    );

    test(
      'a non-restaurant listing has no address/coords/place_id and hasCoords is false',
      () {
        final listing = Listing.fromJson({
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
          // address/latitude/longitude/place_id/hall_count/menu_count/
          // min_menu_price_per_guest all deliberately absent — this is
          // exactly what GET /api/listings sends for a non-venues listing
          // (Go's `omitempty` on every one of those fields).
        });

        expect(listing.address, isNull);
        expect(listing.latitude, isNull);
        expect(listing.longitude, isNull);
        expect(listing.placeId, isNull);
        expect(listing.hasCoords, isFalse);
        expect(listing.capacity, 0);
        expect(listing.hallCount, isNull);
        expect(listing.menuCount, isNull);
        expect(listing.minMenuPricePerGuest, isNull);
        expect(listing.videoUrls, isEmpty);
      },
    );

    test(
      'a restaurant listing with saved coordinates parses latitude/longitude as real numbers, never a string',
      () {
        final listing = Listing.fromJson({
          'id': 16,
          'category_id': 1,
          'name_ru': 'Sultan Palace',
          'name_kz': 'Sultan Palace',
          'description_ru': '',
          'description_kz': '',
          'city': 'Алматы',
          'phone': '',
          'price': 0,
          'min_guests': 0,
          'max_guests': 0,
          'rating': 0,
          'emoji': '',
          'color_from': '',
          'color_to': '',
          'image_urls': [],
          'video_urls': ['/uploads/tour.mp4'],
          'is_active': true,
          'address': 'пр. Абая, 10',
          'latitude': 43.238293,
          'longitude': 76.945465,
          'place_id': 'ChIJtest123',
          'capacity': 300,
          'hall_count': 2,
          'menu_count': 3,
          'min_menu_price_per_guest': 25000,
        });

        expect(listing.address, 'пр. Абая, 10');
        expect(listing.latitude, 43.238293);
        expect(listing.longitude, 76.945465);
        expect(listing.placeId, 'ChIJtest123');
        expect(listing.hasCoords, isTrue);
        expect(listing.capacity, 300);
        expect(listing.hallCount, 2);
        expect(listing.menuCount, 3);
        expect(listing.minMenuPricePerGuest, 25000);
        expect(listing.videoUrls, ['/uploads/tour.mp4']);
      },
    );

    test(
      'a venue with an address but no saved coordinates yet: hasCoords stays false (matches the site\'s own RestaurantLocation.jsx fallback)',
      () {
        final listing = Listing.fromJson({
          'id': 20,
          'category_id': 1,
          'name_ru': 'Без координат',
          'name_kz': 'Без координат',
          'description_ru': '',
          'description_kz': '',
          'city': 'Алматы',
          'phone': '',
          'price': 0,
          'min_guests': 0,
          'max_guests': 0,
          'rating': 0,
          'emoji': '',
          'color_from': '',
          'color_to': '',
          'image_urls': [],
          'is_active': true,
          'address': 'ул. Тестовая, 5',
          // latitude/longitude/place_id still absent
        });

        expect(listing.address, 'ул. Тестовая, 5');
        expect(listing.latitude, isNull);
        expect(listing.longitude, isNull);
        expect(listing.hasCoords, isFalse);
      },
    );
  });

  group('SiteStatistics.fromJson', () {
    test(
      'parses GET /api/site-statistics — plain integers, no "+" baked in',
      () {
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
      },
    );
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

  group('User.fromJson', () {
    test(
      'parses the user object POST /api/auth/login|register and GET /api/auth/me all share',
      () {
        final user = User.fromJson({
          'id': 7,
          'name': 'Айгерим Оспанова',
          'email': 'aigerim@example.com',
          'phone': '+77001234567',
          'role': 'user',
          'status': 'active',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-02T00:00:00Z',
          // password_hash/phone_normalized/telegram_chat_id/
          // preferred_delivery_channel are `json:"-"` on the Go struct —
          // never present in a real response, so intentionally omitted here.
        });

        expect(user.id, 7);
        expect(user.name, 'Айгерим Оспанова');
        expect(user.email, 'aigerim@example.com');
        expect(user.role, 'user');
        expect(user.status, 'active');
        expect(user.isAdmin, isFalse);
        expect(
          user.phoneVerifiedAt,
          isNull,
        ); // always null today, see User's own doc comment
        expect(
          user.telegramLinked,
          isNull,
        ); // only ever set via copyWith after GET /api/auth/me
        expect(user.preferredDeliveryChannel, isNull);
      },
    );

    test('role: admin -> isAdmin true', () {
      final user = User.fromJson({
        'id': 1,
        'name': 'Admin',
        'email': 'admin@mereytoi.kz',
        'phone': '',
        'role': 'admin',
        'status': 'active',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      });
      expect(user.isAdmin, isTrue);
    });

    test(
      'copyWith folds GET /api/auth/me\'s sibling telegram_linked/preferred_delivery_channel onto the base user without touching anything else',
      () {
        final base = User.fromJson({
          'id': 7,
          'name': 'Айгерим',
          'email': 'aigerim@example.com',
          'phone': '',
          'role': 'user',
          'status': 'active',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        });

        final withMeFields = base.copyWith(
          telegramLinked: true,
          preferredDeliveryChannel: 'telegram',
        );

        expect(withMeFields.telegramLinked, isTrue);
        expect(withMeFields.preferredDeliveryChannel, 'telegram');
        expect(withMeFields.id, base.id);
        expect(withMeFields.name, base.name);
        expect(withMeFields.email, base.email);
      },
    );
  });
}
