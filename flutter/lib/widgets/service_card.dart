import 'package:flutter/material.dart';

import '../core/config/api_config.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/format.dart';
import '../models/listing.dart';
import '../screens/provider/provider_profile_screen.dart';
import '../state/locale_provider.dart';
import 'network_image_box.dart';
import 'promotion/ad_label.dart';

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
                  _PhotoFrame(
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
                                            if (listing
                                                    .provider
                                                    ?.displayName
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

/// The services catalog's 2-column grid card: square photo on top (rating
/// badge over it), then the name (always room for 2 lines), city and
/// price pinned to the bottom. Every card in a grid gets the same height
/// from [mainAxisExtent], so long names never make the rows jump.
class ServiceGridCard extends StatelessWidget {
  const ServiceGridCard({
    super.key,
    required this.listing,
    required this.locale,
    required this.onTap,
  });

  final Listing listing;
  final AppLocale locale;
  final VoidCallback onTap;

  static const _titleSize = 14.0;
  static const _titleHeight = 1.25;
  static const _metaSize = 12.0;
  static const _metaHeight = 1.3;
  static const _priceSize = 15.0;
  static const _priceHeight = 1.25;

  /// Text in the card scales with the system font, up to this factor.
  static const maxTextScale = 1.3;

  /// Tighter inner padding on a narrow card (a 320dp phone).
  static double _padding(double width) => width < 160 ? 10 : 12;

  /// The card height for a [width]-wide grid column: the square photo plus
  /// the text block at the given [textScaler].
  static double mainAxisExtent(double width, TextScaler textScaler) {
    final scaler = textScaler.clamp(maxScaleFactor: maxTextScale);
    double line(double size, double height) => scaler.scale(size) * height;
    return width +
        _padding(width) * 2 +
        line(_titleSize, _titleHeight) * 2 +
        4 +
        line(_metaSize, _metaHeight) +
        6 +
        line(_priceSize, _priceHeight) +
        2; // rounding slack
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    final radius = BorderRadius.circular(16);
    final meta = [
      if (listing.city.isNotEmpty) listing.city,
      if (listing.provider?.displayName.isNotEmpty == true)
        listing.provider!.displayName,
      if (listing.capacity > 0) '${listing.capacity}',
    ].join(' · ');

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: maxTextScale,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F1A1611),
              blurRadius: 12,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          color: colors.surface,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final padding = _padding(constraints.maxWidth);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AspectRatio(
                      aspectRatio: 1,
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
                              left: AppSpacing.xs,
                              child: _RatingBadge(rating: listing.rating),
                            ),
                          Positioned(
                            left: AppSpacing.xs,
                            bottom: AppSpacing.xs,
                            child: _ViewCountBadge(
                              count: listing.viewCount,
                              locale: locale,
                            ),
                          ),
                          if (listing.promoted)
                            Positioned(
                              top: AppSpacing.xs,
                              right: AppSpacing.xs,
                              child: AdLabel(locale: locale),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.all(padding),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              listing.name(locale),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: _titleSize,
                                height: _titleHeight,
                                fontWeight: FontWeight.w600,
                                color: colors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (meta.isNotEmpty)
                              Row(
                                children: [
                                  Icon(
                                    Icons.place_outlined,
                                    size: 13,
                                    color: colors.textMuted,
                                  ),
                                  const SizedBox(width: 2),
                                  Expanded(
                                    child: Text(
                                      meta,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: _metaSize,
                                        height: _metaHeight,
                                        color: colors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            const Spacer(),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                formatPrice(listing.price),
                                key: const ValueKey('service-grid-price'),
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: _priceSize,
                                  height: _priceHeight,
                                  fontWeight: FontWeight.w700,
                                  color: colors.goldSoft,
                                ),
                              ),
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
      ),
    );
  }
}

/// A listing's view total over its photo: the same dark pill as the rating, so
/// it reads the same on any photo and in either theme.
class _ViewCountBadge extends StatelessWidget {
  const _ViewCountBadge({required this.count, required this.locale});

  final int count;
  final AppLocale locale;

  @override
  Widget build(BuildContext context) {
    final label = formatCount(count);
    return Semantics(
      label: viewCountSemantics(locale, count),
      excludeSemantics: true,
      child: Container(
        key: const ValueKey('service-view-count'),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.visibility_outlined,
              size: 12,
              color: Colors.white,
            ),
            const SizedBox(width: 3),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
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

/// The list tile's photo (or its placeholder) in a soft frame: clipped to
/// [AppRadius.md], a 1px warm-beige border drawn over the image so the
/// corners stay clean, and a faint shadow that lifts it off the card
/// without a dark smudge. The border colour is mixed from the theme's own
/// surface and gold, so it stays a quiet line in dark mode too.
class _PhotoFrame extends StatelessWidget {
  const _PhotoFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    final radius = BorderRadius.circular(AppRadius.md);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x141A1611),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      position: DecorationPosition.background,
      child: Container(
        foregroundDecoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: Color.alphaBlend(
              colors.goldPrimary.withValues(alpha: 0.15),
              colors.surfaceSoft,
            ),
          ),
        ),
        child: ClipRRect(borderRadius: radius, child: child),
      ),
    );
  }
}
