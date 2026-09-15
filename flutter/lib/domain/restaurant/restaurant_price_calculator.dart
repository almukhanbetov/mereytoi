import '../../models/listing_menu_extra.dart';

/// One priced extra line in a [RestaurantPriceBreakdown] — the extra plus
/// the actual amount it contributed, after unit/guest-count resolution.
class ExtraCalculationLine {
  const ExtraCalculationLine({required this.extra, required this.amount});

  final ListingMenuExtra extra;
  final int amount;
}

/// The result of [RestaurantPriceCalculator.calculate] — mirrors the
/// `breakdown` object frontend/src/components/services/RestaurantMenuCalculator.jsx
/// builds in its `useMemo`, split into the pieces a summary card needs.
class RestaurantPriceBreakdown {
  const RestaurantPriceBreakdown({
    required this.basePrice,
    required this.flatLines,
    required this.percentLines,
    required this.extrasTotal,
    required this.estimatedTotal,
  });

  /// `menu.price_per_guest * guests` — before any extra is applied.
  final int basePrice;

  /// Selected non-percent extras, in `sort_order`, each already resolved to
  /// a flat amount (`price` as-is, or `price * guests` for `per_guest`).
  final List<ExtraCalculationLine> flatLines;

  /// Selected `percent` extras, each computed as
  /// `round((basePrice + flatSum) * extra.price / 100)` — i.e. *after*
  /// flat extras are folded into the subtotal, matching the web calculator
  /// exactly (order matters here).
  final List<ExtraCalculationLine> percentLines;

  /// `sum(flatLines.amount) + sum(percentLines.amount)`.
  final int extrasTotal;

  /// `basePrice + extrasTotal` — the final "Итого".
  final int estimatedTotal;

  List<ExtraCalculationLine> get allLines => [...flatLines, ...percentLines];
}

/// Pure-Dart port of frontend/src/components/services/RestaurantMenuCalculator.jsx's
/// `breakdown` calculation — deliberately duplicated client-side (not called
/// from the backend) because the web app itself never asks the backend to
/// compute this either; the backend only ever stores the resulting
/// `estimated_total` once a booking/cart action is taken. The formula here
/// is taken exactly from that file, not reinterpreted:
///
/// ```
/// subtotal = price_per_guest * guests
/// for each selected extra (sorted by sort_order):
///   if unit == 'percent': percentExtras.push(extra)
///   else: flatExtras.push({extra, amount: unit == 'per_guest' ? price * guests : price})
/// flatSum = sum(flatExtras.amount)
/// beforePercent = subtotal + flatSum
/// percentLines = percentExtras.map(extra => ({extra, amount: round(beforePercent * extra.price / 100)}))
/// total = beforePercent + sum(percentLines.amount)
/// ```
class RestaurantPriceCalculator {
  RestaurantPriceCalculator._();

  static bool isPercentUnit(String unit) =>
      unit.trim().toLowerCase() == 'percent';

  static bool isPerGuestUnit(String unit) =>
      unit.trim().toLowerCase() == 'per_guest';

  static RestaurantPriceBreakdown calculate({
    required int pricePerGuest,
    required int guests,
    required List<ListingMenuExtra> selectedExtras,
  }) {
    final basePrice = pricePerGuest * guests;

    final sorted = [...selectedExtras]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    final flatLines = <ExtraCalculationLine>[];
    final percentExtras = <ListingMenuExtra>[];
    for (final extra in sorted) {
      if (isPercentUnit(extra.unit)) {
        percentExtras.add(extra);
      } else {
        final amount = isPerGuestUnit(extra.unit)
            ? extra.price * guests
            : extra.price;
        flatLines.add(ExtraCalculationLine(extra: extra, amount: amount));
      }
    }

    final flatSum = flatLines.fold<int>(0, (s, l) => s + l.amount);
    final beforePercent = basePrice + flatSum;

    final percentLines = percentExtras
        .map(
          (extra) => ExtraCalculationLine(
            extra: extra,
            amount: (beforePercent * extra.price / 100).round(),
          ),
        )
        .toList();
    final percentSum = percentLines.fold<int>(0, (s, l) => s + l.amount);

    return RestaurantPriceBreakdown(
      basePrice: basePrice,
      flatLines: flatLines,
      percentLines: percentLines,
      extrasTotal: flatSum + percentSum,
      estimatedTotal: beforePercent + percentSum,
    );
  }
}
