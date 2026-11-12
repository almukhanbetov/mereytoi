import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../state/locale_provider.dart';

/// «Реклама» — marks a paid placement. Only a label: no rating, check mark
/// or other badge comes with payment.
class AdLabel extends StatelessWidget {
  const AdLabel({super.key, required this.locale});

  final AppLocale locale;

  static String text(AppLocale locale) =>
      t(locale, ru: 'Реклама', kz: 'Жарнама', en: 'Ad');

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    return Container(
      key: const ValueKey('ad-label'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        text(locale),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: colors.textPrimary,
          height: 1.2,
        ),
      ),
    );
  }
}
