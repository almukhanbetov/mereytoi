import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/domain/restaurant/restaurant_guest_bounds.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/models/listing_menu.dart';

Listing _listing({int minGuests = 0, int maxGuests = 0}) {
  return Listing(
    id: 1,
    categoryId: 1,
    nameRu: 'Sultan Palace',
    nameKz: 'Sultan Palace',
    descriptionRu: '',
    descriptionKz: '',
    city: 'Алматы',
    phone: '',
    price: 0,
    minGuests: minGuests,
    maxGuests: maxGuests,
    rating: 0,
    emoji: '',
    colorFrom: '',
    colorTo: '',
    imageUrls: const [],
    isActive: true,
  );
}

ListingMenu _menu({int? minGuests, int? maxGuests}) {
  return ListingMenu(
    id: 1,
    listingId: 1,
    nameRu: 'Menu',
    nameKz: 'Menu',
    pricePerGuest: 10000,
    minGuests: minGuests,
    maxGuests: maxGuests,
    isActive: true,
    sortOrder: 0,
  );
}

void main() {
  group('resolveGuestBounds', () {
    test("the menu's own min/max win when set", () {
      final bounds = resolveGuestBounds(
        menu: _menu(minGuests: 50, maxGuests: 250),
        listing: _listing(minGuests: 10, maxGuests: 500),
      );
      expect(bounds.min, 50);
      expect(bounds.max, 250);
    });

    test("falls back to the listing's own min/max when the menu has none", () {
      final bounds = resolveGuestBounds(
        menu: _menu(),
        listing: _listing(minGuests: 20, maxGuests: 300),
      );
      expect(bounds.min, 20);
      expect(bounds.max, 300);
    });

    test(
      'max stays null (unbounded) when neither menu nor listing sets one — never invented',
      () {
        final bounds = resolveGuestBounds(
          menu: _menu(minGuests: 30),
          listing: _listing(),
        );
        expect(bounds.min, 30);
        expect(bounds.max, isNull);
      },
    );

    test('min defaults to 1 when nothing at all is set', () {
      final bounds = resolveGuestBounds(menu: _menu(), listing: _listing());
      expect(bounds.min, 1);
      expect(bounds.max, isNull);
    });
  });
}
