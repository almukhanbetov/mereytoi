import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// The one "raised surface" building block — every card in the app should
/// go through this rather than hand-rolling its own `Container` decoration,
/// so depth comes from one consistent soft shadow instead of every screen
/// inventing its own border. No glow, no heavy border by default — those
/// are exactly the "web page" cues this redesign removes.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.color,
    this.radius = AppRadius.lg,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Defaults to the theme's own [MereytoiColors.card] — `null` rather than
  /// a hardcoded `context.mereytoiColors.surface` default so an ordinary `AppCard()`
  /// call automatically looks right in both themes; a caller that wants a
  /// specific surface (e.g. the elevated tone for a "highlighted" card)
  /// still passes one explicitly.
  final Color? color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? context.mereytoiColors.card,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: AppShadows.card,
      ),
      child: child,
    );
  }
}
