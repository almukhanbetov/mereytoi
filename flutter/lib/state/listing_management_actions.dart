import 'package:flutter_riverpod/flutter_riverpod.dart';

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
          imageUrls: current.imageUrls,
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
}

final listingManagementActionsProvider = Provider<ListingManagementActions>(
  (ref) => ListingManagementActions(ref),
);
