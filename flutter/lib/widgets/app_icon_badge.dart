import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// The "circle with an icon centered in it" mark used at the top of every
/// empty/success state in the app (empty cart, no events yet, no search
/// results, a confirmed booking's checkmark, …) — six near-identical
/// hand-rolled `Container`s before Stage 8 unified them into this one
/// widget, so the look only has to be decided once.
class AppIconBadge extends StatelessWidget {
  const AppIconBadge({
    super.key,
    required this.icon,
    this.size = 64,
    this.iconSize = 28,
    this.background,
    this.iconColor,
  });

  final IconData icon;
  final double size;
  final double iconSize;

  /// Both default to the theme's own tokens (`card`/`textSecondary`) rather
  /// than a hardcoded `AppColors` value, so a plain `AppIconBadge(icon:
  /// ...)` already looks right in both themes; pass either explicitly for
  /// a deliberate accent (e.g. gold-on-soft for a success checkmark).
  final Color? background;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? colors.card,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(
        icon,
        size: iconSize,
        color: iconColor ?? colors.textSecondary,
      ),
    );
  }
}
