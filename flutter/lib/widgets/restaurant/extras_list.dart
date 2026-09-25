import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../domain/restaurant/restaurant_price_calculator.dart';
import '../../models/listing_menu_extra.dart';
import '../../state/locale_provider.dart';

/// Brief section 6 — real `ListingMenuExtra` rows only, each showing its
/// name, calculation method (`%` of the running subtotal, a per-guest
/// multiplier, or a flat add-on) and price, exactly the labels
/// RestaurantMenuCalculator.jsx's own extras list uses
/// (`${price}%` / `${formatPrice(price)} / чел.` / `${formatPrice(price)}`).
class ExtrasList extends StatelessWidget {
  const ExtrasList({
    super.key,
    required this.extras,
    required this.selectedIds,
    required this.locale,
    required this.onToggle,
  });

  final List<ListingMenuExtra> extras;
  final Set<int> selectedIds;
  final AppLocale locale;
  final ValueChanged<ListingMenuExtra> onToggle;

  @override
  Widget build(BuildContext context) {
    if (extras.isEmpty) return const SizedBox.shrink();

    final sorted = [...extras]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t(locale, ru: 'Дополнительно', kz: 'Қосымша', en: 'Additional'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.xxs),
        ...sorted.map(
          (extra) => _ExtraRow(
            extra: extra,
            selected: selectedIds.contains(extra.id),
            locale: locale,
            onTap: () => onToggle(extra),
          ),
        ),
      ],
    );
  }
}

class _ExtraRow extends StatelessWidget {
  const _ExtraRow({
    required this.extra,
    required this.selected,
    required this.locale,
    required this.onTap,
  });

  final ListingMenuExtra extra;
  final bool selected;
  final AppLocale locale;
  final VoidCallback onTap;

  String get _priceLabel {
    if (RestaurantPriceCalculator.isPercentUnit(extra.unit)) {
      return '${extra.price}%';
    }
    final base = formatPrice(extra.price);
    return RestaurantPriceCalculator.isPerGuestUnit(extra.unit)
        ? '$base / ${t(locale, ru: "чел.", kz: "адам", en: "guests")}'
        : base;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.xxs),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          constraints: const BoxConstraints(minHeight: 48),
          decoration: BoxDecoration(
            color: selected
                ? context.mereytoiColors.surfaceSoft
                : context.mereytoiColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected
                  ? context.mereytoiColors.goldPrimary
                  : Colors.transparent,
              width: 1.4,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 20,
                color: selected
                    ? context.mereytoiColors.goldPrimary
                    : context.mereytoiColors.textMuted,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  extra.title(locale),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                _priceLabel,
                style: TextStyle(
                  color: context.mereytoiColors.goldSoft,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
