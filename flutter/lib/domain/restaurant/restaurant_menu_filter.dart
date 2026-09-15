import '../../models/listing_hall.dart';
import '../../models/listing_menu.dart';

/// Active menus, sorted by `sort_order` — the exact filter+sort
/// `RestaurantMenus.jsx` applies before anything is rendered
/// (`activeMenus = (listing.menus || []).filter((m) => m.is_active).sort(...)`).
/// The public detail/menus endpoints return the *full* tree (drafts
/// included — the same handler also serves the admin editor), so "inactive
/// menu не показывается" is enforced client-side here, same as on the web.
List<ListingMenu> sortedActiveMenus(List<ListingMenu> menus) {
  final active = menus.where((m) => m.isActive).toList();
  active.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  return active;
}

/// Active halls, same defensive filter `RestaurantMenus.jsx` applies
/// (`activeHalls = (listing.halls || []).filter((h) => h.is_active)`).
/// `GET /api/listings/:id/halls` already only returns active halls
/// server-side, but this keeps the two call sites consistent without
/// assuming that server-side contract from every caller.
List<ListingHall> activeHalls(List<ListingHall> halls) =>
    halls.where((h) => h.isActive).toList();

/// Menus available for a chosen hall: exact match on `hallId`, plus every
/// "any hall" menu (`hallId == null`) — a deliberate mobile-native UX
/// decision for this hall-first flow (the web app doesn't filter by hall at
/// all; see RestaurantMenuChips.jsx, which lists every menu regardless of
/// hall and only shows the hall name as an informational label). Callers
/// should pass [sortedActiveMenus]'s output in — this only narrows by hall.
List<ListingMenu> menusForHall(List<ListingMenu> menus, int? hallId) {
  if (hallId == null) return menus;
  return menus.where((m) => m.hallId == hallId || m.hallId == null).toList();
}
