import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/domain/restaurant/restaurant_menu_filter.dart';
import 'package:mereytoi_app/models/listing_hall.dart';
import 'package:mereytoi_app/models/listing_menu.dart';

ListingMenu _menu({
  required int id,
  int? hallId,
  bool isActive = true,
  int sortOrder = 0,
}) {
  return ListingMenu(
    id: id,
    listingId: 1,
    hallId: hallId,
    nameRu: 'Menu $id',
    nameKz: 'Menu $id',
    pricePerGuest: 10000,
    isActive: isActive,
    sortOrder: sortOrder,
  );
}

ListingHall _hall({required int id, bool isActive = true}) {
  return ListingHall(
    id: id,
    listingId: 1,
    nameRu: 'Hall $id',
    nameKz: 'Hall $id',
    capacity: 100,
    price: 0,
    imageUrls: const [],
    isActive: isActive,
    sortOrder: 0,
  );
}

void main() {
  group('menusForHall', () {
    final matching = _menu(id: 1, hallId: 5);
    final anyHall = _menu(id: 2, hallId: null);
    final otherHall = _menu(id: 3, hallId: 9);
    final menus = [matching, anyHall, otherHall];

    test('keeps a menu whose hallId matches the selected hall', () {
      final result = menusForHall(menus, 5);
      expect(result, contains(matching));
    });

    test('keeps a menu with a null hallId ("any hall")', () {
      final result = menusForHall(menus, 5);
      expect(result, contains(anyHall));
    });

    test('hides a menu tied to a different hall', () {
      final result = menusForHall(menus, 5);
      expect(result, isNot(contains(otherHall)));
      expect(result, hasLength(2));
    });

    test('no hall selected (null) returns every menu unfiltered', () {
      expect(menusForHall(menus, null), menus);
    });
  });

  group(
    'sortedActiveMenus — mirrors RestaurantMenus.jsx\'s activeMenus filter+sort',
    () {
      test('drops inactive menus entirely (not just visually)', () {
        final active = _menu(id: 1, isActive: true);
        final inactive = _menu(id: 2, isActive: false);
        final result = sortedActiveMenus([active, inactive]);
        expect(result, [active]);
      });

      test('sorts the remaining menus by sort_order', () {
        final third = _menu(id: 3, sortOrder: 2);
        final first = _menu(id: 1, sortOrder: 0);
        final second = _menu(id: 2, sortOrder: 1);
        final result = sortedActiveMenus([third, first, second]);
        expect(result.map((m) => m.id), [1, 2, 3]);
      });
    },
  );

  group('activeHalls', () {
    test('drops inactive halls entirely', () {
      final active = _hall(id: 1, isActive: true);
      final inactive = _hall(id: 2, isActive: false);
      expect(activeHalls([active, inactive]), [active]);
    });
  });
}
