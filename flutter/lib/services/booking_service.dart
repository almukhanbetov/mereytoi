import '../core/network/api_client.dart';
import '../models/booking.dart';
import '../models/cart_item.dart';

/// Wraps POST /api/bookings with the exact payload shape
/// backend/internal/handlers/booking_handler.go's `bookingInput` expects:
/// {name, phone, message, items:[{listing_id, name, category, guests,
/// unit_price, total_price}]}. Public endpoint (OptionalAuth) — no token
/// is sent, same as an anonymous checkout on the site.
class BookingService {
  BookingService(this._client);

  final ApiClient _client;

  Future<Booking> submitBooking({
    required String name,
    required String phone,
    String message = '',
    required List<CartItem> items,
  }) async {
    final json = await _client.postJson('/api/bookings', {
      'name': name,
      'phone': phone,
      'message': message,
      'items': items.map((i) => i.toBookingItemJson()).toList(),
    });
    return Booking.fromJson(Map<String, dynamic>.from(json['booking'] as Map));
  }
}
