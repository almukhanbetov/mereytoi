import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/booking.dart';
import 'cart_provider.dart';
import 'providers.dart';

/// Drives the cart screen's submit button: idle → loading → data (success)
/// or error, without the screen ever calling Dio/BookingService directly.
class BookingSubmitNotifier extends StateNotifier<AsyncValue<Booking?>> {
  BookingSubmitNotifier(this._ref) : super(const AsyncData(null));

  final Ref _ref;

  Future<void> submit({required String name, required String phone, String message = ''}) async {
    final items = _ref.read(cartProvider);
    if (items.isEmpty) return;

    state = const AsyncLoading();
    try {
      final booking = await _ref.read(bookingServiceProvider).submitBooking(
            name: name,
            phone: phone,
            message: message,
            items: items,
          );
      // Only clear the cart once the API has actually confirmed the
      // booking — a failed request must leave the cart exactly as it was.
      _ref.read(cartProvider.notifier).clear();
      state = AsyncData(booking);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  /// Resets to idle — called when the cart items change again after a
  /// success/error screen, so a new attempt starts clean.
  void reset() => state = const AsyncData(null);
}

final bookingSubmitProvider = StateNotifierProvider<BookingSubmitNotifier, AsyncValue<Booking?>>((ref) {
  return BookingSubmitNotifier(ref);
});
