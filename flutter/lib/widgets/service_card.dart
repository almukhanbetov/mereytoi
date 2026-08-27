import 'package:flutter/material.dart';

import '../core/config/api_config.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/format.dart';
import '../models/listing.dart';
import '../state/locale_provider.dart';
import 'network_image_box.dart';

/// A compact vertical card — used in horizontal carousels (Home's
/// "Популярные услуги"). The primary services list uses
/// [ServiceListTile] instead (a horizontal layout with more room to
/// breathe); this stays for contexts that need a narrow, scannable tile.
/// Every text line is single-line + ellipsis and the price sits in a
/// `FittedBox`, so it cannot overflow regardless of name length, locale,
/// or the device's font-scale setting.
class ServiceCard extends StatelessWidget {
  const ServiceCard({super.key, required this.listing, required this.locale, required this.categoryLabel, required this.onTap});

  final Listing listing;
  final AppLocale locale;
  final String? categoryLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1.15,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  NetworkImageBox(url: ApiConfig.mediaUrl(listing.coverImage), borderRadius: 0, fallbackIcon: Icons.celebration_outlined),
                  if (listing.rating > 0)
                    Positioned(
                      top: AppSpacing.xs,
                      right: AppSpacing.xs,
                      child: _RatingBadge(rating: listing.rating),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (categoryLabel != null && categoryLabel!.isNotEmpty)
                    Text(
                      categoryLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.goldMuted),
                    ),
                  const SizedBox(height: 3),
                  Text(
                    listing.name(locale),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  if (listing.city.isNotEmpty)
                    Text(
                      listing.city,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: AppSpacing.xs),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      formatPrice(listing.price),
                      maxLines: 1,
                      style: const TextStyle(color: AppColors.goldSoft, fontWeight: FontWeight.w700, fontSize: 14.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The primary services-list row — a horizontal card (image left, info
/// right). Chosen over a 2-column grid for the main catalog: listing names
/// vary a lot in length, and a wide single column gives text room to
/// breathe without any risk of the squeeze that caused overflow in a
/// narrow grid tile.
class ServiceListTile extends StatelessWidget {
  const ServiceListTile({super.key, required this.listing, required this.locale, required this.categoryLabel, required this.onTap});

  final Listing listing;
  final AppLocale locale;
  final String? categoryLabel;
  final VoidCallback onTap;

  static const double _height = 104;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // ~32% of the card's own width, per the "30–35%" spec — clamped
              // so it stays sane on both a 360px phone and a tablet-ish width.
              final imageSize = (constraints.maxWidth * 0.32).clamp(84.0, 128.0);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: SizedBox(
                      width: imageSize,
                      height: _height,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          NetworkImageBox(url: ApiConfig.mediaUrl(listing.coverImage), borderRadius: 0, fallbackIcon: Icons.celebration_outlined),
                          // Rating moves onto the photo (a top-app marketplace
                          // convention) instead of competing with the price
                          // for space in the text column below.
                          if (listing.rating > 0)
                            Positioned(top: AppSpacing.xxs, left: AppSpacing.xxs, child: _RatingBadge(rating: listing.rating)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: SizedBox(
                      height: _height,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (categoryLabel != null && categoryLabel!.isNotEmpty)
                                Text(
                                  categoryLabel!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.goldMuted),
                                ),
                              const SizedBox(height: 3),
                              Text(
                                listing.name(locale),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (listing.city.isNotEmpty)
                                Expanded(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.place_outlined, size: 13, color: AppColors.textMuted),
                                      const SizedBox(width: 3),
                                      Flexible(
                                        child: Text(listing.city, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                const Spacer(),
                              const SizedBox(width: AppSpacing.xs),
                              // Held to its own content width, styled quietly
                              // (not a shouting display size) — "заметная, но
                              // не кричащая" — with a FittedBox as a hard
                              // safety net against arbitrarily long prices.
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    formatPrice(listing.price),
                                    maxLines: 1,
                                    style: const TextStyle(color: AppColors.goldSoft, fontWeight: FontWeight.w700, fontSize: 14.5),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _RatingBadge extends StatelessWidget {
  const _RatingBadge({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 12, color: AppColors.goldPrimary),
          const SizedBox(width: 2),
          Text(rating.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
