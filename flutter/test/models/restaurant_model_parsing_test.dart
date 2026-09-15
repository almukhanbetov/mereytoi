import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/models/listing_hall.dart';
import 'package:mereytoi_app/models/listing_menu.dart';
import 'package:mereytoi_app/models/listing_menu_extra.dart';
import 'package:mereytoi_app/models/listing_menu_item.dart';
import 'package:mereytoi_app/models/listing_menu_section.dart';
import 'package:mereytoi_app/state/locale_provider.dart';

void main() {
  group('ListingHall.fromJson', () {
    test('parses a real GET /api/listings/:id/halls row', () {
      final hall = ListingHall.fromJson({
        'id': 1,
        'listing_id': 16,
        'name_ru': 'Sultan Hall',
        'name_kz': 'Sultan Hall',
        'description_ru': '',
        'description_kz': '',
        'capacity': 300,
        'price': 0,
        'image_urls': ['/uploads/hall1.jpg'],
        'is_active': true,
        'sort_order': 0,
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      });

      expect(hall.id, 1);
      expect(hall.listingId, 16);
      expect(hall.name(AppLocale.ru), 'Sultan Hall');
      expect(hall.capacity, 300);
      expect(hall.price, 0); // 0 == "inherit the listing's own price"
      expect(hall.coverImage, '/uploads/hall1.jpg');
      expect(hall.isActive, isTrue);
    });

    test(
      'is_active: false round-trips correctly (the GORM default-tag bug this backend already fixed)',
      () {
        final hall = ListingHall.fromJson({
          'id': 2,
          'listing_id': 16,
          'name_ru': 'Скрытый зал',
          'name_kz': 'Скрытый зал',
          'capacity': 0,
          'price': 0,
          'image_urls': [],
          'is_active': false,
          'sort_order': 1,
        });
        expect(hall.isActive, isFalse);
      },
    );
  });

  group('ListingMenuItem/Section/Extra.fromJson', () {
    test('item parses quantity_text and optional descriptions', () {
      final item = ListingMenuItem.fromJson({
        'id': 5,
        'section_id': 3,
        'name_ru': 'Мясное ассорти',
        'name_kz': 'Ет ассортиси',
        'description_ru': 'Буженина, язык',
        'quantity_text': '250 г',
        'sort_order': 0,
      });
      expect(item.name(AppLocale.ru), 'Мясное ассорти');
      expect(item.quantityText, '250 г');
      expect(
        item.description(AppLocale.kz),
        '',
      ); // description_kz absent -> default ''
    });

    test('section nests its items array (menuSectionOut shape)', () {
      final section = ListingMenuSection.fromJson({
        'id': 3,
        'menu_id': 1,
        'title_ru': 'Холодные закуски',
        'title_kz': 'Салқын тағамдар',
        'sort_order': 0,
        'items': [
          {
            'id': 5,
            'section_id': 3,
            'name_ru': 'Мясное ассорти',
            'name_kz': 'Ет ассортиси',
            'sort_order': 0,
          },
        ],
      });
      expect(section.title(AppLocale.kz), 'Салқын тағамдар');
      expect(section.items, hasLength(1));
      expect(section.items.single.nameRu, 'Мясное ассорти');
    });

    test(
      'a bare section with no items key (admin CRUD response shape) defaults to an empty list',
      () {
        final section = ListingMenuSection.fromJson({
          'id': 3,
          'menu_id': 1,
          'title_ru': 'X',
          'title_kz': 'Y',
          'sort_order': 0,
        });
        expect(section.items, isEmpty);
      },
    );

    test(
      'extra: type/unit/price are the real free-form backend fields, no invented enum',
      () {
        final extra = ListingMenuExtra.fromJson({
          'id': 9,
          'menu_id': 1,
          'type': 'service_fee',
          'title_ru': 'Сервисный сбор',
          'title_kz': 'Қызмет ақысы',
          'price': 10,
          'unit': 'percent',
          'sort_order': 0,
        });
        expect(extra.type, 'service_fee');
        expect(extra.unit, 'percent');
        expect(extra.price, 10);
      },
    );
  });

  group('ListingMenu.fromJson', () {
    test(
      'parses the full menuOut shape (menu + sections + extras) from GET /api/listings/:id',
      () {
        final menu = ListingMenu.fromJson({
          'id': 1,
          'listing_id': 16,
          'hall_id': 1,
          'name_ru': 'Меню 25000',
          'name_kz': 'Меню 25000',
          'price_per_guest': 25000,
          'min_guests': 50,
          'max_guests': 250,
          'is_active': true,
          'sort_order': 0,
          'valid_from': '2026-09-10T00:00:00Z',
          'valid_until': '2026-12-31T00:00:00Z',
          'sections': [
            {
              'id': 3,
              'menu_id': 1,
              'title_ru': 'Холодные закуски',
              'title_kz': 'Салқын тағамдар',
              'sort_order': 0,
              'items': [],
            },
          ],
          'extras': [
            {
              'id': 9,
              'menu_id': 1,
              'type': 'kids_table',
              'title_ru': 'Детский стол',
              'title_kz': 'Балалар үстелі',
              'price': 12000,
              'unit': 'per_guest',
              'sort_order': 0,
            },
          ],
        });

        expect(menu.hallId, 1);
        expect(menu.pricePerGuest, 25000);
        expect(menu.minGuests, 50);
        expect(menu.maxGuests, 250);
        expect(menu.validFrom, isNotNull);
        expect(menu.sections, hasLength(1));
        expect(menu.extras, hasLength(1));
      },
    );

    test('hall_id absent -> null, meaning "any hall" (never coerced to 0)', () {
      final menu = ListingMenu.fromJson({
        'id': 2,
        'listing_id': 16,
        'name_ru': 'Меню без зала',
        'name_kz': 'Меню без зала',
        'price_per_guest': 15000,
        'is_active': true,
        'sort_order': 1,
      });
      expect(menu.hallId, isNull);
      expect(
        menu.minGuests,
        isNull,
      ); // never defaulted to 0 — a real constraint vs "not set" must stay distinguishable
      expect(menu.maxGuests, isNull);
      expect(menu.sections, isEmpty);
      expect(menu.extras, isEmpty);
    });
  });
}
