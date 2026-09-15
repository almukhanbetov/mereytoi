import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// A compact, soft-filled pill. Unselected chips sit on a *neutral* fill
/// (never gold-tinted — gold is reserved for the selected state), so a row
/// of filter chips never reads as "everything is gold."
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xxs,
          ),
          decoration: BoxDecoration(
            // Unselected sits on the same quiet tone as a resting card, not
            // the brighter "soft" fill (which reads as too light/washed out
            // for a whole row of inactive chips).
            color: selected ? colors.goldPrimary : colors.card,
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: selected ? colors.onGold : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// A tiny inline pill for a single fact (city, rating, phone).
class AppMetaChip extends StatelessWidget {
  const AppMetaChip({
    super.key,
    required this.icon,
    required this.label,
    this.iconColor,
  });

  final IconData icon;
  final String label;

  /// Defaults to the theme's own secondary text color when omitted — kept
  /// nullable (rather than a hardcoded `AppColors` default) so it responds
  /// to light/dark automatically unless a caller deliberately wants a
  /// specific accent (e.g. gold for a rating star).
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: iconColor ?? colors.textSecondary),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
    );
  }
}
