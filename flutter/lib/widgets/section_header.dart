import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// A section title with a small gold eyebrow above it — used once or twice
/// per screen for the "app-like" hierarchy the redesign asks for (a clear
/// title, not a wall of decorative text).
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.eyebrow, required this.title});

  final String eyebrow;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow.toUpperCase(),
          style: const TextStyle(color: AppColors.goldPrimary, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 1.6),
        ),
        const SizedBox(height: 4),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
      ],
    );
  }
}
