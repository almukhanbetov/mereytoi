import 'listing.dart';
import 'restaurant_selection.dart';

/// Identity of one cart line: an ordinary service is unique by
/// `listingId` alone (`hallId`/`menuId` both null); a restaurant is unique
/// by `(listingId, hallId, menuId)` — two different halls/menus of the same
/// listing are two different cart items, matching
/// `CartDrawer.jsx`'s own `${item.listingId}:${item.hallId || ''}:${item.menuId || ''}`
/// React key. A record, not a class: records already have structural
/// `==`/`hashCode`, so no hand-written equality is needed to use this as a
/// `Set`/comparison key.
typedef CartItemKey = ({int listingId, int? hallId, int? menuId});

/// A line in the local booking cart — same shape the site keeps in
/// localStorage (frontend/src/context/AppProviders.jsx's cart `items`)
/// and the same shape POST /api/bookings expects per item
/// (backend/internal/handlers/booking_handler.go's `bookingItemInput`).
///
/// The `hallId`/`hallName`/`menuId`/`menuName`/`menuPricePerGuest`/
/// `selectedExtras`/`estimatedTotal` fields are Stage 3's addition — all
/// nullable/defaulted, so an ordinary service's `CartItem.fromListing` is
/// completely unaffected: it never sets any of them, exactly as before.
/// `guests` deliberately stays the one field it already was — a
/// restaurant's guest count reuses it rather than adding a second,
/// near-duplicate field, the same call `CartDrawer.jsx` already makes.
class CartItem {
  const CartItem({
    required this.listingId,
    required this.name,
    required this.category,
    required this.image,
    required this.unitPrice,
    required this.guests,
    required this.totalPrice,
    this.hallId,
    this.hallName,
    this.menuId,
    this.menuName,
    this.menuPricePerGuest,
    this.selectedExtras = const [],
    this.estimatedTotal,
  });

  final int listingId;
  final String name;
  final String category;
  final String? image;
  final int unitPrice;
  final int
  guests; // 0 for flat-priced listings, matching the site's convention
  final int totalPrice;

  // ---- Restaurant/venue variant snapshot (Stage 3) — all null/empty for
  // an ordinary service. Once added, none of these are re-derived from the
  // live listing/menu API again (brief section 11 — a later admin price
  // change must never silently reprice an item already in someone's cart).
  final int? hallId;
  final String? hallName;
  final int? menuId;
  final String? menuName;
  final int? menuPricePerGuest;
  final List<SelectedExtraLine> selectedExtras;
  final int? estimatedTotal;

  /// The identity this item dedupes/removes by — see [CartItemKey]'s own
  /// doc comment.
  CartItemKey get key => (listingId: listingId, hallId: hallId, menuId: menuId);

  /// Is this a restaurant/venue variant, not an ordinary service? Same
  /// test `cart_screen.dart`'s own card and the checkout validation rely
  /// on — a hall or a menu was picked.
  bool get isRestaurantVariant => hallId != null || menuId != null;

  /// Builds a cart entry the same way the site's ServiceDetail.jsx does:
  /// per-person listings multiply guests × price, otherwise it's the flat
  /// listing price. `name`/`categoryLabel` are passed in already resolved
  /// to the current locale, same as the site resolves them at add-time.
  factory CartItem.fromListing(
    Listing listing, {
    required String name,
    required String categoryLabel,
    int guests = 1,
  }) {
    final isPerPerson = listing.isPerPerson;
    final effectiveGuests = isPerPerson ? guests : 0;
    final total = isPerPerson ? guests * listing.price : listing.price;
    return CartItem(
      listingId: listing.id,
      name: name,
      category: categoryLabel,
      image: listing.coverImage,
      unitPrice: listing.price,
      guests: effectiveGuests,
      totalPrice: total,
    );
  }

  /// Builds a restaurant/venue cart entry from a Stage-2 [RestaurantSelection]
  /// — the exact field mapping `handleAddToCart` uses in
  /// RestaurantMenuCalculator.jsx: `name` becomes `"<listing> · <menu>"`,
  /// `unitPrice` is the menu's per-guest price, `totalPrice` is the fully
  /// priced `estimatedTotal` (base + extras), and every restaurant-only
  /// field below is a snapshot taken *now* — see this class's own doc
  /// comment on why none of it gets recomputed later.
  factory CartItem.fromRestaurantSelection(
    RestaurantSelection selection, {
    required String listingName,
    required String categoryLabel,
    String? image,
  }) {
    return CartItem(
      listingId: selection.listingId,
      name: '$listingName · ${selection.menuName}',
      category: categoryLabel,
      image: image,
      unitPrice: selection.menuPricePerGuest,
      guests: selection.guests,
      totalPrice: selection.estimatedTotal,
      hallId: selection.hallId,
      hallName: selection.hallName,
      menuId: selection.menuId,
      menuName: selection.menuName,
      menuPricePerGuest: selection.menuPricePerGuest,
      selectedExtras: selection.selectedExtras,
      estimatedTotal: selection.estimatedTotal,
    );
  }

  /// Local persistence (shared_preferences, see `CartStorage`) — the full
  /// variant snapshot, not just `listingId`, so a restored cart is
  /// byte-identical to what was there before the app closed.
  Map<String, dynamic> toJson() => {
    'listing_id': listingId,
    'name': name,
    'category': category,
    'image': image,
    'unit_price': unitPrice,
    'guests': guests,
    'total_price': totalPrice,
    'hall_id': hallId,
    'hall_name': hallName,
    'menu_id': menuId,
    'menu_name': menuName,
    'menu_price_per_guest': menuPricePerGuest,
    'selected_extras': selectedExtras.map((e) => e.toJson()).toList(),
    'estimated_total': estimatedTotal,
  };

  /// Migration-safe: a cart saved by an earlier version of this app (before
  /// Stage 3) never wrote `hall_id`/`menu_id`/`selected_extras`/
  /// `estimated_total` at all — every one of those keys is read as
  /// optional here, falling back to null/`[]`, never throwing on a missing
  /// key.
  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      listingId: json['listing_id'] as int,
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? '',
      image: json['image'] as String?,
      unitPrice: json['unit_price'] as int? ?? 0,
      guests: json['guests'] as int? ?? 0,
      totalPrice: json['total_price'] as int? ?? 0,
      hallId: json['hall_id'] as int?,
      hallName: json['hall_name'] as String?,
      menuId: json['menu_id'] as int?,
      menuName: json['menu_name'] as String?,
      menuPricePerGuest: json['menu_price_per_guest'] as int?,
      selectedExtras:
          (json['selected_extras'] as List?)
              ?.map(
                (e) => SelectedExtraLine.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ),
              )
              .toList() ??
          const [],
      estimatedTotal: json['estimated_total'] as int?,
    );
  }

  /// The exact shape `POST /api/bookings` expects per item
  /// (`bookingItemInput` in backend/internal/handlers/booking_handler.go) —
  /// `hall_id`/`menu_id`/etc. are simply `null`/empty for an ordinary
  /// service, which the handler already treats as "not a restaurant item",
  /// unchanged from before Stage 3. `selected_extras` here intentionally
  /// carries only `{title, price, unit}` — the one shape
  /// `bookingItemExtraInput` declares — not the extra `amount` this app
  /// also keeps locally for its own summary UI.
  Map<String, dynamic> toBookingItemJson() => {
    'listing_id': listingId,
    'name': name,
    'category': category,
    'guests': guests,
    'unit_price': unitPrice,
    'total_price': totalPrice,
    'hall_id': hallId,
    'hall_name': hallName ?? '',
    'menu_id': menuId,
    'menu_name': menuName ?? '',
    'menu_price_per_guest': menuPricePerGuest ?? 0,
    'selected_extras': selectedExtras
        .map((e) => {'title': e.title, 'price': e.price, 'unit': e.unit})
        .toList(),
    'estimated_total': estimatedTotal ?? 0,
  };
}
