import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/restaurant/restaurant_guest_bounds.dart';
import '../../state/locale_provider.dart';

/// Brief section 5 — a `[-] N гостей [+]` stepper, bounds coming from
/// [GuestBounds] (already resolved: menu's own min/max, falling back to the
/// listing's, with no invented cap when genuinely absent).
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
    final max = bounds.max;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          t(locale, ru: 'Количество гостей', kz: 'Қонақтар саны'),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StepButton(
              icon: Icons.remove_rounded,
              onTap: guests > bounds.min ? () => onChanged(guests - 1) : null,
            ),
            SizedBox(
              width: 64,
              child: Text(
                '$guests ${t(locale, ru: "чел.", kz: "адам")}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            _StepButton(
              icon: Icons.add_rounded,
              onTap: (max == null || guests < max)
                  ? () => onChanged(guests + 1)
                  : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: enabled
          ? context.mereytoiColors.surfaceSoft
          : context.mereytoiColors.surface,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            icon,
            size: 17,
            color: enabled
                ? context.mereytoiColors.goldPrimary
                : context.mereytoiColors.textMuted,
          ),
        ),
      ),
    );
  }
}
