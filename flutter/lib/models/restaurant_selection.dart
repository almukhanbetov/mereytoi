import '../domain/restaurant/restaurant_price_calculator.dart';
import '../state/locale_provider.dart';

/// One selected/priced extra, exactly the shape
/// `breakdown.selected` builds on the web (RestaurantMenuCalculator.jsx's
/// `{title: extra.title_ru, price: extra.price, unit: extra.unit || ''}`),
/// with `amount` added on top — the actual contribution this extra made to
/// the total (already resolved for guests/percent), not just its raw
/// catalog `price`.
class SelectedExtraLine {
  const SelectedExtraLine({
    required this.title,
    required this.price,
    required this.unit,
    required this.amount,
  });

  final String title;
  final int price;
  final String unit;
  final int amount;

  factory SelectedExtraLine.fromJson(Map<String, dynamic> json) {
    return SelectedExtraLine(
      title: json['title'] as String? ?? '',
      price: json['price'] as int? ?? 0,
      unit: json['unit'] as String? ?? '',
      amount: json['amount'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'price': price,
    'unit': unit,
    'amount': amount,
  };
}

/// Stage-2 output of the restaurant screen: everything a Stage-3 cart item
/// / booking payload / manager-chat context will eventually need, mirroring
/// the field set `handleAddToCart`/`handleAskManager` in
/// RestaurantMenuCalculator.jsx already build on the web. Deliberately NOT
/// a cart rewrite — this is just the plain data the sticky CTA hands off;
/// nothing here touches `CartItem` or `CartNotifier`.
class RestaurantSelection {
  const RestaurantSelection({
    required this.listingId,
    this.hallId,
    this.hallName,
    required this.menuId,
    required this.menuName,
    required this.menuPricePerGuest,
    required this.guests,
    required this.selectedExtras,
    required this.estimatedTotal,
  });

  final int listingId;
  final int? hallId;
  final String? hallName;
  final int menuId;
  final String menuName;
  final int menuPricePerGuest;
  final int guests;
  final List<SelectedExtraLine> selectedExtras;
  final int estimatedTotal;

  /// Builds a selection from a resolved [RestaurantPriceBreakdown] — the
  /// same `hallId: hall?.id || menu.hall_id || null` fallback the web uses,
  /// and `selected` built from the breakdown's own priced lines (not the
  /// raw extra catalog), so `selectedExtras` always reflects what was
  /// actually charged.
  factory RestaurantSelection.fromBreakdown({
    required int listingId,
    int? hallId,
    String? hallName,
    required int menuId,
    required String menuName,
    required int menuPricePerGuest,
    required int guests,
    required RestaurantPriceBreakdown breakdown,
    required AppLocale locale,
  }) {
    return RestaurantSelection(
      listingId: listingId,
      hallId: hallId,
      hallName: hallName,
      menuId: menuId,
      menuName: menuName,
      menuPricePerGuest: menuPricePerGuest,
      guests: guests,
      selectedExtras: breakdown.allLines
          .map(
            (line) => SelectedExtraLine(
              title: line.extra.title(locale),
              price: line.extra.price,
              unit: line.extra.unit,
              amount: line.amount,
            ),
          )
          .toList(),
      estimatedTotal: breakdown.estimatedTotal,
    );
  }

  Map<String, dynamic> toJson() => {
    'listing_id': listingId,
    'hall_id': hallId,
    'hall_name': hallName,
    'menu_id': menuId,
    'menu_name': menuName,
    'menu_price_per_guest': menuPricePerGuest,
    'guests': guests,
    'selected_extras': selectedExtras.map((e) => e.toJson()).toList(),
    'estimated_total': estimatedTotal,
  };
}
