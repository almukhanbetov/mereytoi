/// Mirrors `models.BookingItemExtra` (backend/internal/models/booking.go) —
/// the same three fields `bookingItemExtraInput` accepts, echoed back
/// unchanged on the stored/returned item.
class BookingItemExtra {
  const BookingItemExtra({
    required this.title,
    required this.price,
    required this.unit,
  });

  final String title;
  final int price;
  final String unit;

  factory BookingItemExtra.fromJson(Map<String, dynamic> json) {
    return BookingItemExtra(
      title: json['title'] as String? ?? '',
      price: json['price'] as int? ?? 0,
      unit: json['unit'] as String? ?? '',
    );
  }
}

/// Mirrors `models.BookingItem` — the exact snapshot the backend stored,
/// echoed back on the `booking` object POST /api/bookings responds with.
/// Read directly from the server's own response rather than re-derived
/// from the local cart, so the success screen/PDF show precisely what was
/// actually saved (brief section 3 — "не пересчитывать").
class BookingItem {
  const BookingItem({
    required this.listingId,
    required this.name,
    required this.category,
    required this.guests,
    required this.unitPrice,
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
  final int guests;
  final int unitPrice;
  final int totalPrice;
  final int? hallId;
  final String? hallName;
  final int? menuId;
  final String? menuName;
  final int? menuPricePerGuest;
  final List<BookingItemExtra> selectedExtras;
  final int? estimatedTotal;

  /// Same test the cart UI already uses — a hall or a menu was picked.
  bool get isRestaurantVariant => hallId != null || menuId != null;

  factory BookingItem.fromJson(Map<String, dynamic> json) {
    return BookingItem(
      listingId: json['listing_id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? '',
      guests: json['guests'] as int? ?? 0,
      unitPrice: json['unit_price'] as int? ?? 0,
      totalPrice: json['total_price'] as int? ?? 0,
      hallId: json['hall_id'] as int?,
      hallName: (json['hall_name'] as String?)?.isEmpty ?? true
          ? null
          : json['hall_name'] as String,
      menuId: json['menu_id'] as int?,
      menuName: (json['menu_name'] as String?)?.isEmpty ?? true
          ? null
          : json['menu_name'] as String,
      menuPricePerGuest: json['menu_price_per_guest'] as int?,
      selectedExtras:
          (json['selected_extras'] as List?)
              ?.map(
                (e) => BookingItemExtra.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ),
              )
              .toList() ??
          const [],
      estimatedTotal: json['estimated_total'] as int?,
    );
  }
}

/// Mirrors the `booking` object POST /api/bookings responds with
/// (backend/internal/models/booking.go's `Booking`) — the full record, not
/// just id/status, so the success screen and PDF export can be built
/// directly from what the server actually saved.
class Booking {
  const Booking({
    required this.id,
    required this.publicRef,
    required this.name,
    required this.phone,
    required this.message,
    required this.items,
    required this.total,
    required this.status,
    this.userId,
    this.eventId,
    this.createdAt,
  });

  final int id;
  final String publicRef;
  final String name;
  final String phone;
  final String message;
  final List<BookingItem> items;
  final int total;
  final String status;
  final int? userId;
  // Set for a booking created from/linked to an Event Workspace request —
  // never present for an ordinary cart checkout (see EventRequestHandler's
  // own approval flow) except via the onboarding pipeline below, which can
  // attach a brand-new event to an anonymous checkout after the fact.
  final int? eventId;
  final DateTime? createdAt;

  factory Booking.fromJson(Map<String, dynamic> json) {
    return Booking(
      id: json['id'] as int? ?? 0,
      publicRef: json['public_ref'] as String? ?? '',
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      message: json['message'] as String? ?? '',
      items:
          (json['items'] as List?)
              ?.map(
                (e) =>
                    BookingItem.fromJson(Map<String, dynamic>.from(e as Map)),
              )
              .toList() ??
          const [],
      total: json['total'] as int? ?? 0,
      status: json['status'] as String? ?? 'new',
      userId: json['user_id'] as int?,
      eventId: json['event_id'] as int?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
    );
  }
}

/// Mirrors `onboardingResult` (backend/internal/handlers/onboarding.go) —
/// present only when `BookingHandler.Create`'s best-effort booking→account
/// pipeline actually did something (brief section 14): AUTO_ACCOUNT_FROM_
/// BOOKING is on, the booking was genuinely anonymous, and it had no event
/// yet. `null` on [BookingCreateResult.onboarding] is the normal case and
/// must render nothing extra, exactly like `BookingWorkspaceCTA.jsx`'s own
/// `if (!onboarding) return null;`.
class BookingOnboarding {
  const BookingOnboarding({
    required this.status,
    this.eventId,
    this.claimToken,
    this.deliveryStatus,
    this.deliveryChannel,
  });

  /// "created_pending" | "pending_claim" | "existing_account" — never
  /// anything else; matched exactly, never guessed at.
  final String status;
  final int? eventId;
  final String? claimToken;

  /// Only ever present when a delivery attempt actually happened — see the
  /// Go struct's own doc comment on why this is `omitempty`, not a default
  /// empty string.
  final String? deliveryStatus;
  final String? deliveryChannel;

  factory BookingOnboarding.fromJson(Map<String, dynamic> json) {
    return BookingOnboarding(
      status: json['status'] as String? ?? '',
      eventId: json['event_id'] as int?,
      claimToken: json['claim_token'] as String?,
      deliveryStatus: json['delivery_status'] as String?,
      deliveryChannel: json['delivery_channel'] as String?,
    );
  }
}

/// The full `POST /api/bookings` response — `{booking, onboarding?}`.
class BookingCreateResult {
  const BookingCreateResult({required this.booking, this.onboarding});

  final Booking booking;
  final BookingOnboarding? onboarding;

  factory BookingCreateResult.fromJson(Map<String, dynamic> json) {
    return BookingCreateResult(
      booking: Booking.fromJson(
        Map<String, dynamic>.from(json['booking'] as Map),
      ),
      onboarding: json['onboarding'] == null
          ? null
          : BookingOnboarding.fromJson(
              Map<String, dynamic>.from(json['onboarding'] as Map),
            ),
    );
  }
}
