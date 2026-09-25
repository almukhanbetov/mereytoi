import 'package:flutter/material.dart';

import '../core/config/api_config.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/format.dart';
import '../models/listing.dart';
import '../screens/provider/provider_profile_screen.dart';
import '../state/locale_provider.dart';
import 'network_image_box.dart';

/// A compact vertical card — used in horizontal carousels (Home's
/// "Популярные услуги" and "Рестораны"). The primary services list uses
/// [ServiceListTile] instead (a horizontal layout with more room to
/// breathe); this stays for contexts that need a narrow, scannable tile.
/// Every text line is bounded (2 lines for the name, 1 for everything
/// else) + ellipsis, and the price sits in a `FittedBox`, so nothing here
/// can overflow regardless of name length, locale, or the device's
/// font-scale setting.
class ServiceCard extends StatelessWidget {
  const ServiceCard({
    super.key,
    required this.listing,
    required this.locale,
    required this.categoryLabel,
    required this.onTap,
  });

  final Listing listing;
  final AppLocale locale;
  final String? categoryLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.card,
      ),
      child: Material(
        color: colors.surface,
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
                    NetworkImageBox(
                      url: ApiConfig.mediaUrl(listing.coverImage),
                      borderRadius: 0,
                      fallbackIcon: Icons.celebration_outlined,
                    ),
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
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.goldMuted,
                        ),
                      ),
                    const SizedBox(height: 3),
                    Text(
                      listing.name(locale),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.titleSmall?.copyWith(height: 1.2),
                    ),
                    const SizedBox(height: 3),
                    if (listing.city.isNotEmpty || listing.capacity > 0)
                      Row(
                        children: [
                          if (listing.city.isNotEmpty)
                            Flexible(
                              child: Text(
                                listing.city,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          if (listing.city.isNotEmpty && listing.capacity > 0)
                            Text(
                              '  ·  ',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          if (listing.capacity > 0)
                            Icon(
                              Icons.groups_outlined,
                              size: 12,
                              color: colors.textMuted,
                            ),
                          if (listing.capacity > 0)
                            Text(
                              ' ${listing.capacity}',
                              maxLines: 1,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    // Этап 11 "Provider Marketplace" — null for every
                    // listing with no self-serve provider owner (every
                    // admin-created listing predating this stage). Этап
                    // 11G: tappable, opens the public provider profile —
                    // a nested `GestureDetector` inside the card's own
                    // `InkWell` above, which Flutter's gesture arena lets
                    // win for taps landing exactly here.
                    if (listing.provider?.displayName.isNotEmpty == true)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: listing.provider!.id == 0
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ProviderProfileScreen(
                                    providerId: listing.provider!.id,
                                  ),
                                ),
                              ),
                        child: Text(
                          listing.provider!.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.textMuted),
                        ),
                      ),
                    const SizedBox(height: AppSpacing.xs),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        formatPrice(listing.price),
                        maxLines: 1,
                        style: TextStyle(
                          color: colors.goldSoft,
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
  const ServiceListTile({
    super.key,
    required this.listing,
    required this.locale,
    required this.categoryLabel,
    required this.onTap,
  });

  final Listing listing;
  final AppLocale locale;
  final String? categoryLabel;
  final VoidCallback onTap;

  static const double _height = 104;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.mereytoiColors.surface,
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
              final imageSize = (constraints.maxWidth * 0.32).clamp(
                84.0,
                128.0,
              );
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
                          NetworkImageBox(
                            url: ApiConfig.mediaUrl(listing.coverImage),
                            borderRadius: 0,
                            fallbackIcon: Icons.celebration_outlined,
                          ),
                          // Rating moves onto the photo (a top-app marketplace
                          // convention) instead of competing with the price
                          // for space in the text column below.
                          if (listing.rating > 0)
                            Positioned(
                              top: AppSpacing.xxs,
                              left: AppSpacing.xxs,
                              child: _RatingBadge(rating: listing.rating),
                            ),
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
                              if (categoryLabel != null &&
                                  categoryLabel!.isNotEmpty)
                                Text(
                                  categoryLabel!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: context.mereytoiColors.goldMuted,
                                      ),
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
                              if (listing.city.isNotEmpty ||
                                  listing.capacity > 0 ||
                                  listing.provider?.displayName.isNotEmpty ==
                                      true)
                                Expanded(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        listing.city.isNotEmpty
                                            ? Icons.place_outlined
                                            : Icons.groups_outlined,
                                        size: 13,
                                        color: context.mereytoiColors.textMuted,
                                      ),
                                      const SizedBox(width: 3),
                                      // A single ellipsizing Text, not a Row
                                      // of separate icon/number widgets: this
                                      // sits inside an `Expanded` that itself
                                      // splits space 50/50 with the price's
                                      // own `Flexible` below, so any fixed-
                                      // width sibling here (an extra icon, a
                                      // bare separator) can outlive its own
                                      // half-share and force a real
                                      // RenderFlex overflow on a narrow
                                      // screen — a single `Flexible(Text)`
                                      // is the only shape that's guaranteed
                                      // to just ellipsize instead. Provider
                                      // name (Этап 11) folds into this same
                                      // single Text for the same reason —
                                      // this tile's height is fixed
                                      // (`_height`), so a provider listing
                                      // can't grow a whole extra line.
                                      Flexible(
                                        child: Text(
                                          [
                                            if (listing.provider?.displayName
                                                    .isNotEmpty ==
                                                true)
                                              listing.provider!.displayName,
                                            if (listing.city.isNotEmpty)
                                              listing.city,
                                            if (listing.capacity > 0)
                                              '${listing.capacity}',
                                          ].join(' · '),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
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
                                    style: TextStyle(
                                      color: context.mereytoiColors.goldSoft,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14.5,
                                    ),
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
          Icon(
            Icons.star_rounded,
            size: 12,
            color: context.mereytoiColors.goldPrimary,
          ),
          const SizedBox(width: 2),
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
