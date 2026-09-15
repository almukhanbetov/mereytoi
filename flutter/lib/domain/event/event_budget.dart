import '../../models/event_candidate.dart';

/// Exact Dart port of frontend/src/lib/eventHelpers.js's `candidateEstimate`
/// — one candidate's contribution to the budget, used by the Budget tab's
/// per-candidate breakdown (`GET /api/events/:id/summary` only returns
/// aggregate numbers, no per-item figure). Never recomputes a restaurant
/// menu from a live API call: `estimatedTotal`/`menuPricePerGuest` are
/// already-frozen snapshots taken at `AddCandidate` time (see
/// `EventCandidate`'s own doc comment) — this only combines numbers
/// already on the candidate (or, for a non-restaurant candidate, the
/// listing's own flat `price`).
///
/// JS truthy semantics preserved deliberately: a `0` `estimatedTotal`/
/// `menuPricePerGuest` falls through to the next branch exactly like the
/// web helper does (`candidate.estimated_total` is falsy when it's 0).
int candidateEstimate(EventCandidate candidate, {required int eventGuests}) {
  final estimatedTotal = candidate.estimatedTotal;
  if (candidate.menuId != null &&
      estimatedTotal != null &&
      estimatedTotal != 0) {
    return estimatedTotal;
  }

  final pricePerGuest = candidate.menuPricePerGuest;
  if (candidate.menuId != null && pricePerGuest != null && pricePerGuest != 0) {
    final guests = (candidate.guests != null && candidate.guests != 0)
        ? candidate.guests!
        : eventGuests;
    return pricePerGuest * guests;
  }

  return candidate.listing?.price ?? 0;
}
