import 'package:flutter/material.dart';

import '../core/config/api_config.dart';
import '../core/theme/app_theme.dart';
import '../models/category.dart';
import '../state/locale_provider.dart';
import 'network_image_box.dart';

/// A photo tile for a category — image, a soft gradient for legibility, and
/// the name pinned to the bottom. Kept photo-forward (this is the one place
/// in the redesign that's still "image card", intentionally) but tightened
/// radius/typography/spacing to match the rest of the new system.
class CategoryCard extends StatelessWidget {
  const CategoryCard({
    super.key,
    required this.category,
    required this.locale,
    required this.onTap,
  });

  final Category category;
  final AppLocale locale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.mereytoiColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: AspectRatio(
          aspectRatio: 0.92,
          child: Stack(
            fit: StackFit.expand,
            children: [
              NetworkImageBox(
                url: ApiConfig.mediaUrl(category.imageUrl),
                borderRadius: 0,
                fallbackIcon: Icons.auto_awesome,
              ),
              // Legibility scrim: the top of the photo stays untouched, the
              // bottom ~45% darkens progressively so the name reads on both
              // light and dark photos without a heavy black band.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.25),
                      Colors.black.withValues(alpha: 0.74),
                    ],
                    stops: const [0.45, 0.68, 1.0],
                  ),
                ),
              ),
              Positioned(
                left: 15,
                right: 15,
                bottom: 16,
                child: Text(
                  category.name(locale),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  // Always light: the name sits on the photo's dark scrim in
                  // both themes (the theme's titleSmall colour is dark in
                  // light mode, which made it unreadable on photos).
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.18,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
