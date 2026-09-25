import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../domain/restaurant/restaurant_price_calculator.dart';
import '../../state/locale_provider.dart';
import '../animated_price_text.dart';
import '../app_card.dart';

/// Brief section 8 — the price breakdown card, "Итого" visually dominant.
/// When the menu genuinely has no price (`pricePerGuest == 0` — never set
/// by the admin), this never claims a false "0 ₸": it shows
/// "Цена по запросу" instead, and the line-item breakdown (which would
/// otherwise be all zeros) is skipped entirely.
class PriceSummaryCard extends StatelessWidget {
  const PriceSummaryCard({
    super.key,
    required this.pricePerGuest,
    required this.guests,
    required this.breakdown,
    required this.locale,
  });

  final int pricePerGuest;
  final int guests;
  final RestaurantPriceBreakdown breakdown;
  final AppLocale locale;

  @override
  Widget build(BuildContext context) {
    final hasRealPrice = pricePerGuest > 0;

    return AppCard(
      color: context.mereytoiColors.surfaceElevated,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasRealPrice) ...[
            _Line(
              '$guests ${t(locale, ru: "гостей", kz: "қонақ", en: "guests")} × ${formatPrice(pricePerGuest)}',
              formatPrice(breakdown.basePrice),
            ),
            for (final line in breakdown.flatLines)
              _Line(
                '+ ${line.extra.title(locale)}',
                '+ ${formatPrice(line.amount)}',
              ),
            for (final line in breakdown.percentLines)
              _Line(
                '+ ${line.extra.title(locale)} (${line.extra.price}%)',
                '+ ${formatPrice(line.amount)}',
              ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Divider(height: 1),
            ),
          ],
          // Этап 10Б-1А fix: neither child here was ever Expanded — at a
          // large system text scale, "Итого" (titleLarge) plus a genuinely
          // large multi-digit total (22px bold) can exceed the card's
          // width, and a Row with two unconstrained children overflows
          // instead of adapting. Wrap (same technique as the
          // MenuContentAccordion header fix) keeps the same spaced layout
          // when it fits, and drops the total to its own line — still
          // fully readable, never clipped or shrunk — when it doesn't.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: AppSpacing.xxs,
            children: [
              Text(
                t(locale, ru: 'Итого', kz: 'Барлығы', en: 'Total'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              AnimatedPriceText(
                text: hasRealPrice
                    ? formatPrice(breakdown.estimatedTotal)
                    : t(
                        locale,
                        ru: 'Цена по запросу',
                        kz: 'Сұрау бойынша баға',
                        en: 'Price on request',
                      ),
                style: TextStyle(
                  color: context.mereytoiColors.goldSoft,
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.mereytoiColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
