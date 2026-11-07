import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/restaurant/menu_text_import.dart';
import '../models/listing.dart';
import '../models/listing_hall.dart';
import '../models/listing_menu.dart';
import '../models/listing_menu_extra.dart';
import '../models/listing_menu_item.dart';
import '../models/listing_menu_section.dart';
import 'listings_provider.dart';
import 'providers.dart';

/// Every hall for this listing regardless of `is_active` — see
/// `ListingManagementService.fetchAllHalls`'s own doc comment on why the
/// management UI can't reuse the public [listingHallsProvider] (active-only
/// filter would hide an inactive hall from ever being re-activated).
final listingAllHallsProvider = FutureProvider.family<List<ListingHall>, int>((
  ref,
  listingId,
) {
  return ref.watch(listingManagementServiceProvider).fetchAllHalls(listingId);
});

/// Every restaurant-management mutation (listing/hall/menu/section/item/
/// extra), each followed by invalidating exactly the providers that just
/// went stale — same "plain async methods + invalidate" shape
/// `NotificationActions`/`EventActions` already established. Invalidating
/// [listingHallsProvider]/[listingMenusProvider] here is *also* what makes
/// the public `RestaurantDetailScreen` pick up a change with no app
/// restart: it watches those exact same two providers, so the next time
/// it (or this management screen) rebuilds, Riverpod refetches for real.
class ListingManagementActions {
  ListingManagementActions(this._ref);

  final Ref _ref;

  void _invalidateListing(int listingId) {
    _ref.invalidate(listingDetailProvider(listingId));
    _ref.invalidate(listingHallsProvider(listingId));
    _ref.invalidate(listingAllHallsProvider(listingId));
    _ref.invalidate(listingMenusProvider(listingId));
    // The venues rail on Home and the admin "Рестораны и локации" list
    // both read the unfiltered/venues listingsProvider — a name/city edit
    // should show up there too without a restart.
    _ref.invalidate(listingsProvider(null));
    _ref.invalidate(listingsProvider('venues'));
    // «Мои рестораны» shows the name and the hall and menu counts.
    _ref.invalidate(myListingsProvider);
  }

  Future<Listing> updateListing(
    Listing current, {
    String? nameRu,
    String? nameKz,
    String? descriptionRu,
    String? descriptionKz,
    String? city,
    String? phone,
    int? price,
    int? minGuests,
    int? maxGuests,
    String? address,
    double? latitude,
    double? longitude,
    String? placeId,
    int? capacity,
    bool clearCoordinates = false,
  }) async {
    final result = await _ref
        .read(listingManagementServiceProvider)
        .updateListing(
          current,
          nameRu: nameRu,
          nameKz: nameKz,
          descriptionRu: descriptionRu,
          descriptionKz: descriptionKz,
          city: city,
          phone: phone,
          price: price,
          minGuests: minGuests,
          maxGuests: maxGuests,
          address: address,
          latitude: latitude,
          longitude: longitude,
          placeId: placeId,
          capacity: capacity,
          clearCoordinates: clearCoordinates,
        );
    _invalidateListing(current.id);
    return result;
  }

  Future<ListingHall> createHall(
    int listingId, {
    required String nameRu,
    required String nameKz,
    String descriptionRu = '',
    String descriptionKz = '',
    int capacity = 0,
    int price = 0,
    List<String> imageUrls = const [],
    bool isActive = true,
    int sortOrder = 0,
  }) async {
    final result = await _ref
        .read(listingManagementServiceProvider)
        .createHall(
          listingId,
          nameRu: nameRu,
          nameKz: nameKz,
          descriptionRu: descriptionRu,
          descriptionKz: descriptionKz,
          capacity: capacity,
          price: price,
          imageUrls: imageUrls,
          isActive: isActive,
          sortOrder: sortOrder,
        );
    _invalidateListing(listingId);
    return result;
  }

  Future<ListingHall> updateHall(
    int listingId,
    ListingHall current, {
    required String nameRu,
    required String nameKz,
    String descriptionRu = '',
    String descriptionKz = '',
    int capacity = 0,
    int price = 0,
    List<String>? imageUrls,
    bool isActive = true,
    int sortOrder = 0,
  }) async {
    final result = await _ref
        .read(listingManagementServiceProvider)
        .updateHall(
          listingId,
          current.id,
          nameRu: nameRu,
          nameKz: nameKz,
          descriptionRu: descriptionRu,
          descriptionKz: descriptionKz,
          capacity: capacity,
          price: price,
          imageUrls: imageUrls ?? current.imageUrls,
          isActive: isActive,
          sortOrder: sortOrder,
        );
    _invalidateListing(listingId);
    return result;
  }

  Future<void> deleteHall(int listingId, int hallId) async {
    await _ref
        .read(listingManagementServiceProvider)
        .deleteHall(listingId, hallId);
    _invalidateListing(listingId);
  }

  Future<ListingMenu> createMenu(
    int listingId, {
    int? hallId,
    required String nameRu,
    required String nameKz,
    String descriptionRu = '',
    String descriptionKz = '',
    int pricePerGuest = 0,
    int? minGuests,
    int? maxGuests,
    bool isActive = true,
    int sortOrder = 0,
    DateTime? validFrom,
    DateTime? validUntil,
  }) async {
    final result = await _ref
        .read(listingManagementServiceProvider)
        .createMenu(
          listingId,
          hallId: hallId,
          nameRu: nameRu,
          nameKz: nameKz,
          descriptionRu: descriptionRu,
          descriptionKz: descriptionKz,
          pricePerGuest: pricePerGuest,
          minGuests: minGuests,
          maxGuests: maxGuests,
          isActive: isActive,
          sortOrder: sortOrder,
          validFrom: validFrom,
          validUntil: validUntil,
        );
    _invalidateListing(listingId);
    return result;
  }

  Future<ListingMenu> updateMenu(
    int listingId,
    int menuId, {
    int? hallId,
    required String nameRu,
    required String nameKz,
    String descriptionRu = '',
    String descriptionKz = '',
    int pricePerGuest = 0,
    int? minGuests,
    int? maxGuests,
    bool isActive = true,
    int sortOrder = 0,
    DateTime? validFrom,
    DateTime? validUntil,
  }) async {
    final result = await _ref
        .read(listingManagementServiceProvider)
        .updateMenu(
          listingId,
          menuId,
          hallId: hallId,
          nameRu: nameRu,
          nameKz: nameKz,
          descriptionRu: descriptionRu,
          descriptionKz: descriptionKz,
          pricePerGuest: pricePerGuest,
          minGuests: minGuests,
          maxGuests: maxGuests,
          isActive: isActive,
          sortOrder: sortOrder,
          validFrom: validFrom,
          validUntil: validUntil,
        );
    _invalidateListing(listingId);
    return result;
  }

  Future<void> deleteMenu(int listingId, int menuId) async {
    await _ref
        .read(listingManagementServiceProvider)
        .deleteMenu(listingId, menuId);
    _invalidateListing(listingId);
  }

  Future<ListingMenuSection> createSection(
    int listingId,
    int menuId, {
    required String titleRu,
    required String titleKz,
    int sortOrder = 0,
  }) async {
    final result = await _ref
        .read(listingManagementServiceProvider)
        .createSection(
          listingId,
          menuId,
          titleRu: titleRu,
          titleKz: titleKz,
          sortOrder: sortOrder,
        );
    _invalidateListing(listingId);
    return result;
  }

  Future<ListingMenuSection> updateSection(
    int listingId,
    int menuId,
    int sectionId, {
    required String titleRu,
    required String titleKz,
    int sortOrder = 0,
  }) async {
    final result = await _ref
        .read(listingManagementServiceProvider)
        .updateSection(
          listingId,
          menuId,
          sectionId,
          titleRu: titleRu,
          titleKz: titleKz,
          sortOrder: sortOrder,
        );
    _invalidateListing(listingId);
    return result;
  }

  Future<void> deleteSection(int listingId, int menuId, int sectionId) async {
    await _ref
        .read(listingManagementServiceProvider)
        .deleteSection(listingId, menuId, sectionId);
    _invalidateListing(listingId);
  }

  Future<ListingMenuItem> createItem(
    int listingId,
    int menuId,
    int sectionId, {
    required String nameRu,
    required String nameKz,
    String descriptionRu = '',
    String descriptionKz = '',
    String quantityText = '',
    int sortOrder = 0,
  }) async {
    final result = await _ref
        .read(listingManagementServiceProvider)
        .createItem(
          listingId,
          menuId,
          sectionId,
          nameRu: nameRu,
          nameKz: nameKz,
          descriptionRu: descriptionRu,
          descriptionKz: descriptionKz,
          quantityText: quantityText,
          sortOrder: sortOrder,
        );
    _invalidateListing(listingId);
    return result;
  }

  Future<ListingMenuItem> updateItem(
    int listingId,
    int menuId,
    int sectionId,
    int itemId, {
    required String nameRu,
    required String nameKz,
    String descriptionRu = '',
    String descriptionKz = '',
    String quantityText = '',
    int sortOrder = 0,
  }) async {
    final result = await _ref
        .read(listingManagementServiceProvider)
        .updateItem(
          listingId,
          menuId,
          sectionId,
          itemId,
          nameRu: nameRu,
          nameKz: nameKz,
          descriptionRu: descriptionRu,
          descriptionKz: descriptionKz,
          quantityText: quantityText,
          sortOrder: sortOrder,
        );
    _invalidateListing(listingId);
    return result;
  }

  Future<void> deleteItem(
    int listingId,
    int menuId,
    int sectionId,
    int itemId,
  ) async {
    await _ref
        .read(listingManagementServiceProvider)
        .deleteItem(listingId, menuId, sectionId, itemId);
    _invalidateListing(listingId);
  }

  Future<ListingMenuExtra> createExtra(
    int listingId,
    int menuId, {
    required String type,
    required String titleRu,
    required String titleKz,
    int price = 0,
    String unit = '',
    String descriptionRu = '',
    String descriptionKz = '',
    int sortOrder = 0,
  }) async {
    final result = await _ref
        .read(listingManagementServiceProvider)
        .createExtra(
          listingId,
          menuId,
          type: type,
          titleRu: titleRu,
          titleKz: titleKz,
          price: price,
          unit: unit,
          descriptionRu: descriptionRu,
          descriptionKz: descriptionKz,
          sortOrder: sortOrder,
        );
    _invalidateListing(listingId);
    return result;
  }

  Future<ListingMenuExtra> updateExtra(
    int listingId,
    int menuId,
    int extraId, {
    required String type,
    required String titleRu,
    required String titleKz,
    int price = 0,
    String unit = '',
    String descriptionRu = '',
    String descriptionKz = '',
    int sortOrder = 0,
  }) async {
    final result = await _ref
        .read(listingManagementServiceProvider)
        .updateExtra(
          listingId,
          menuId,
          extraId,
          type: type,
          titleRu: titleRu,
          titleKz: titleKz,
          price: price,
          unit: unit,
          descriptionRu: descriptionRu,
          descriptionKz: descriptionKz,
          sortOrder: sortOrder,
        );
    _invalidateListing(listingId);
    return result;
  }

  Future<void> deleteExtra(int listingId, int menuId, int extraId) async {
    await _ref
        .read(listingManagementServiceProvider)
        .deleteExtra(listingId, menuId, extraId);
    _invalidateListing(listingId);
  }

  // ---- list commands the admin offers: show/hide, order, copy, import ----

  bool _running = false;

  /// One list command at a time, so a second tap can't interleave its writes.
  Future<void> _exclusive(
    int listingId,
    Future<void> Function() command,
  ) async {
    if (_running) return;
    _running = true;
    try {
      await command();
    } finally {
      _running = false;
      _invalidateListing(listingId);
    }
  }

  Future<void> _putHall(
    int listingId,
    ListingHall h, {
    bool? isActive,
    int? sortOrder,
  }) {
    return _ref
        .read(listingManagementServiceProvider)
        .updateHall(
          listingId,
          h.id,
          nameRu: h.nameRu,
          nameKz: h.nameKz,
          descriptionRu: h.descriptionRu,
          descriptionKz: h.descriptionKz,
          capacity: h.capacity,
          price: h.price,
          imageUrls: h.imageUrls,
          isActive: isActive ?? h.isActive,
          sortOrder: sortOrder ?? h.sortOrder,
        );
  }

  Future<void> _putMenu(
    int listingId,
    ListingMenu m, {
    bool? isActive,
    int? sortOrder,
  }) {
    return _ref
        .read(listingManagementServiceProvider)
        .updateMenu(
          listingId,
          m.id,
          hallId: m.hallId,
          nameRu: m.nameRu,
          nameKz: m.nameKz,
          descriptionRu: m.descriptionRu,
          descriptionKz: m.descriptionKz,
          pricePerGuest: m.pricePerGuest,
          minGuests: m.minGuests,
          maxGuests: m.maxGuests,
          isActive: isActive ?? m.isActive,
          sortOrder: sortOrder ?? m.sortOrder,
          validFrom: m.validFrom,
          validUntil: m.validUntil,
        );
  }

  Future<void> setHallActive(int listingId, ListingHall hall, bool active) =>
      _exclusive(listingId, () => _putHall(listingId, hall, isActive: active));

  Future<void> setMenuActive(int listingId, ListingMenu menu, bool active) =>
      _exclusive(listingId, () => _putMenu(listingId, menu, isActive: active));

  // Reorders write each row's position, not a swap of two values: rows created
  // earlier in the app may all share sort_order 0, and a swap wouldn't move them.
  Future<void> reorderHalls(int listingId, List<ListingHall> ordered) =>
      _exclusive(listingId, () async {
        for (var i = 0; i < ordered.length; i++) {
          if (ordered[i].sortOrder != i) {
            await _putHall(listingId, ordered[i], sortOrder: i);
          }
        }
      });

  Future<void> reorderMenus(int listingId, List<ListingMenu> ordered) =>
      _exclusive(listingId, () async {
        for (var i = 0; i < ordered.length; i++) {
          if (ordered[i].sortOrder != i) {
            await _putMenu(listingId, ordered[i], sortOrder: i);
          }
        }
      });

  Future<void> reorderSections(
    int listingId,
    int menuId,
    List<ListingMenuSection> ordered,
  ) => _exclusive(listingId, () async {
    final service = _ref.read(listingManagementServiceProvider);
    for (var i = 0; i < ordered.length; i++) {
      final s = ordered[i];
      if (s.sortOrder == i) continue;
      await service.updateSection(
        listingId,
        menuId,
        s.id,
        titleRu: s.titleRu,
        titleKz: s.titleKz,
        sortOrder: i,
      );
    }
  });

  Future<void> reorderItems(
    int listingId,
    int menuId,
    int sectionId,
    List<ListingMenuItem> ordered,
  ) => _exclusive(listingId, () async {
    final service = _ref.read(listingManagementServiceProvider);
    for (var i = 0; i < ordered.length; i++) {
      final item = ordered[i];
      if (item.sortOrder == i) continue;
      await service.updateItem(
        listingId,
        menuId,
        sectionId,
        item.id,
        nameRu: item.nameRu,
        nameKz: item.nameKz,
        descriptionRu: item.descriptionRu,
        descriptionKz: item.descriptionKz,
        quantityText: item.quantityText,
        sortOrder: i,
      );
    }
  });

  /// A hidden copy at the end of the list, as in the admin.
  Future<void> duplicateHall(
    int listingId,
    ListingHall h, {
    required int count,
  }) => _exclusive(listingId, () async {
    await _ref
        .read(listingManagementServiceProvider)
        .createHall(
          listingId,
          nameRu: '${h.nameRu} (копия)',
          nameKz: h.nameKz.isNotEmpty
              ? '${h.nameKz} (көшірме)'
              : '${h.nameRu} (көшірме)',
          descriptionRu: h.descriptionRu,
          descriptionKz: h.descriptionKz,
          capacity: h.capacity,
          price: h.price,
          imageUrls: h.imageUrls,
          isActive: false,
          sortOrder: count,
        );
  });

  /// A hidden copy with its sections, items and extras, as in the admin.
  Future<void> duplicateMenu(
    int listingId,
    ListingMenu m, {
    required int count,
  }) => _exclusive(listingId, () async {
    final service = _ref.read(listingManagementServiceProvider);
    final copy = await service.createMenu(
      listingId,
      hallId: m.hallId,
      nameRu: '${m.nameRu} — копия',
      nameKz: m.nameKz.isNotEmpty
          ? '${m.nameKz} — көшірме'
          : '${m.nameRu} — көшірме',
      descriptionRu: m.descriptionRu,
      descriptionKz: m.descriptionKz,
      pricePerGuest: m.pricePerGuest,
      minGuests: m.minGuests,
      maxGuests: m.maxGuests,
      isActive: false,
      sortOrder: count,
      validFrom: m.validFrom,
      validUntil: m.validUntil,
    );
    for (final section in m.sections) {
      final newSection = await service.createSection(
        listingId,
        copy.id,
        titleRu: section.titleRu,
        titleKz: section.titleKz,
        sortOrder: section.sortOrder,
      );
      for (final item in section.items) {
        await service.createItem(
          listingId,
          copy.id,
          newSection.id,
          nameRu: item.nameRu,
          nameKz: item.nameKz,
          descriptionRu: item.descriptionRu,
          descriptionKz: item.descriptionKz,
          quantityText: item.quantityText,
          sortOrder: item.sortOrder,
        );
      }
    }
    for (final extra in m.extras) {
      await service.createExtra(
        listingId,
        copy.id,
        type: extra.type,
        titleRu: extra.titleRu,
        titleKz: extra.titleKz,
        price: extra.price,
        unit: extra.unit,
        descriptionRu: extra.descriptionRu,
        descriptionKz: extra.descriptionKz,
        sortOrder: extra.sortOrder,
      );
    }
  });

  Future<void> importMenuSections(
    int listingId,
    int menuId,
    List<MenuTextSection> sections, {
    required int existingSectionCount,
  }) => _exclusive(listingId, () async {
    final service = _ref.read(listingManagementServiceProvider);
    var order = existingSectionCount;
    for (final section in sections) {
      final created = await service.createSection(
        listingId,
        menuId,
        titleRu: section.title,
        titleKz: section.title,
        sortOrder: order++,
      );
      for (var i = 0; i < section.items.length; i++) {
        final item = section.items[i];
        await service.createItem(
          listingId,
          menuId,
          created.id,
          nameRu: item.name,
          nameKz: item.name,
          quantityText: item.quantityText,
          sortOrder: i,
        );
      }
    }
  });
}

final listingManagementActionsProvider = Provider<ListingManagementActions>(
  (ref) => ListingManagementActions(ref),
);
