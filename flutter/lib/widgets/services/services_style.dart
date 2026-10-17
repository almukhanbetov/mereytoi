import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Shared look of the services catalog's filter blocks (city, search,
/// category tiles): one radius and one barely-there shadow, so the three
/// blocks read as one light system.
const kServicesRadius = 16.0;

/// A white card with a hairline border and a minimal shadow — much lighter
/// than [AppShadows.card], which is tuned for photo cards.
BoxDecoration servicesCardDecoration(
  BuildContext context, {
  Color? color,
  Color? borderColor,
  double borderWidth = 1,
}) {
  final colors = context.mereytoiColors;
  return BoxDecoration(
    color: color ?? colors.surface,
    borderRadius: BorderRadius.circular(kServicesRadius),
    border: Border.all(color: borderColor ?? colors.border, width: borderWidth),
    boxShadow: const [
      BoxShadow(color: Color(0x0A1A1611), blurRadius: 6, offset: Offset(0, 2)),
    ],
  );
}
