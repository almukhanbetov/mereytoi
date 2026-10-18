/// One booking request that includes the provider's own services — mirrors
/// GET /api/provider/me/bookings (backend/internal/handlers/
/// provider_bookings.go). Only the provider's own items and their subtotal
/// are present, never another provider's lines.
class ProviderBooking {
  const ProviderBooking({
    required this.id,
    required this.publicRef,
    required this.status,
    required this.createdAt,
    required this.clientName,
    required this.clientPhone,
    required this.message,
    required this.items,
    required this.total,
    this.eventDate,
  });

  final int id;
  final String publicRef;

  /// new / contacted / confirmed / cancelled.
  final String status;
  final DateTime createdAt;
  final DateTime? eventDate;
  final String clientName;
  final String clientPhone;
  final String message;
  final List<ProviderBookingItem> items;
  final int total;

  factory ProviderBooking.fromJson(Map<String, dynamic> json) {
    return ProviderBooking(
      id: json['id'] as int,
      publicRef: json['public_ref'] as String? ?? '',
      status: json['status'] as String? ?? 'new',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      eventDate: DateTime.tryParse(json['event_date'] as String? ?? ''),
      clientName: json['client_name'] as String? ?? '',
      clientPhone: json['client_phone'] as String? ?? '',
      message: json['message'] as String? ?? '',
      items: [
        for (final e in json['items'] as List? ?? const [])
          ProviderBookingItem.fromJson(Map<String, dynamic>.from(e as Map)),
      ],
      total: json['total'] as int? ?? 0,
    );
  }
}

class ProviderBookingItem {
  const ProviderBookingItem({
    required this.listingId,
    required this.title,
    required this.totalPrice,
    this.guests = 0,
  });

  final int listingId;
  final String title;
  final int totalPrice;
  final int guests;

  factory ProviderBookingItem.fromJson(Map<String, dynamic> json) {
    return ProviderBookingItem(
      listingId: json['listing_id'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      totalPrice: json['total_price'] as int? ?? 0,
      guests: json['guests'] as int? ?? 0,
    );
  }
}
