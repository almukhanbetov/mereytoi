import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/booking.dart';
import 'cart_provider.dart';
import 'providers.dart';

/// Drives the checkout screen's submit button: idle → loading → data
/// (success, carrying the server's own `{booking, onboarding}`) or error,
/// without the screen ever calling Dio/BookingService directly.
class BookingSubmitNotifier
    extends StateNotifier<AsyncValue<BookingCreateResult?>> {
  BookingSubmitNotifier(this._ref) : super(const AsyncData(null));

  final Ref _ref;

  Future<void> submit({
    required String name,
    required String phone,
    String message = '',
  }) async {
    // Re-entrancy guard — a double-tap, a rebuild while the request is
    // still in flight, or a resumed navigation must never fire a second
    // real POST /api/bookings. A completed success (AsyncData(non-null))
    // is also refused here: once a booking exists, retrying must go
    // through `reset()` first (a fresh, deliberate action), not a second
    // call that would silently double-book.
    if (state is AsyncLoading) return;
    if (state case AsyncData(:final value) when value != null) return;

    final items = _ref.read(cartProvider);
    if (items.isEmpty) return;

    state = const AsyncLoading();
    try {
      final result = await _ref
          .read(bookingServiceProvider)
          .submitBooking(
            name: name,
            phone: phone,
            message: message,
            items: items,
          );
      // Only clear the cart once the API has actually confirmed the
      // booking — a failed request must leave the cart exactly as it was.
      _ref.read(cartProvider.notifier).clear();
      state = AsyncData(result);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  /// Resets to idle — called after the success screen is dismissed, or
  /// before a genuinely new attempt (never called automatically, so a
  /// finished success/error state never silently re-arms itself).
  void reset() => state = const AsyncData(null);
}

final bookingSubmitProvider =
    StateNotifierProvider<
      BookingSubmitNotifier,
      AsyncValue<BookingCreateResult?>
    >((ref) {
      return BookingSubmitNotifier(ref);
    });
