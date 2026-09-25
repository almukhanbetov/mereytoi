import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/restaurant/restaurant_guest_bounds.dart';
import '../../state/locale_provider.dart';
import '../numeric_stepper_field.dart';

/// Brief section 5 — guest count editor, bounds coming from [GuestBounds]
/// (already resolved: menu's own min/max, falling back to the listing's,
/// with no invented cap when genuinely absent). Этап 10Б-1: type the
/// number directly, tap a quick value, or nudge by one — see
/// [NumericStepperField], the one shared implementation of this
/// interaction (this screen and the ordinary per-person service both used
/// to hand-roll their own "+/− only" version).
class GuestSelector extends StatelessWidget {
  const GuestSelector({
    super.key,
    required this.guests,
    required this.bounds,
    required this.locale,
    required this.onChanged,
  });

  final int guests;
  final GuestBounds bounds;
  final AppLocale locale;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t(
            locale,
            ru: 'Количество гостей',
            kz: 'Қонақтар саны',
            en: 'Number of guests',
          ),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: AppSpacing.xs),
        NumericStepperField(
          value: guests,
          min: bounds.min,
          max: bounds.max,
          suffixLabel: t(locale, ru: 'чел.', kz: 'адам', en: 'guests'),
          quickPickLabel: t(
            locale,
            ru: 'Быстрый выбор гостей',
            kz: 'Қонақтарды жылдам таңдау',
            en: 'Quick guest picks',
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
