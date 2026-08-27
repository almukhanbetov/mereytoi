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
  const CategoryCard({super.key, required this.category, required this.locale, required this.onTap});

  final Category category;
  final AppLocale locale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: AspectRatio(
          aspectRatio: 0.92,
          child: Stack(
            fit: StackFit.expand,
            children: [
              NetworkImageBox(url: ApiConfig.mediaUrl(category.imageUrl), borderRadius: 0, fallbackIcon: Icons.auto_awesome),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.58)],
                    stops: const [0.58, 1.0],
                  ),
                ),
              ),
              Positioned(
                left: AppSpacing.sm,
                right: AppSpacing.sm,
                bottom: AppSpacing.sm,
                child: Text(
                  category.name(locale),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
