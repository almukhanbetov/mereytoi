import '../../models/cart_item.dart';

/// Every reason [validateCartForCheckout] can refuse to let the user reach
/// the submit button — pure and UI-agnostic so the checkout screen just
/// switches on it for copy, and tests don't need to render anything to
/// exercise each branch.
enum CheckoutBlockReason { emptyCart, missingEstimatedTotal, invalidGuestCount }

typedef CheckoutValidation = ({bool isValid, CheckoutBlockReason? reason});

/// Pre-checkout sanity check (brief section 4 — "перед checkout
/// провалидировать корзину"). Deliberately does NOT re-fetch or re-verify
/// against any live listing/menu: every guest-count bound a restaurant
/// variant has to respect was already enforced by the selector UI at the
/// moment it was added to the cart (see `resolveGuestBounds`), so a value
/// already sitting in the cart is valid by construction — re-checking it
/// here against fresh server data would be exactly the "recompute after
/// the fact" the brief explicitly forbids for a frozen snapshot. What this
/// *does* check is internal consistency of the snapshot itself: every
/// restaurant variant must actually have a guest count and a priced total,
/// since those are the two fields the checkout screen and the booking
/// payload both depend on.
CheckoutValidation validateCartForCheckout(List<CartItem> items) {
  if (items.isEmpty) {
    return (isValid: false, reason: CheckoutBlockReason.emptyCart);
  }
  for (final item in items) {
    if (!item.isRestaurantVariant) continue;
    if (item.guests <= 0) {
      return (isValid: false, reason: CheckoutBlockReason.invalidGuestCount);
    }
    if (item.estimatedTotal == null) {
      return (
        isValid: false,
        reason: CheckoutBlockReason.missingEstimatedTotal,
      );
    }
  }
  return (isValid: true, reason: null);
}

/// A standalone guest-count/bounds check — used wherever a hall/menu's own
/// `min_guests`/`max_guests` (see `resolveGuestBounds`) needs to be
/// compared against a candidate guest count, e.g. before letting the user
/// change the guest count on an existing cart line. `max == null` means no
/// upper bound to enforce.
bool isGuestCountWithinBounds(int guests, {required int min, int? max}) {
  if (guests < min) return false;
  if (max != null && guests > max) return false;
  return true;
}
