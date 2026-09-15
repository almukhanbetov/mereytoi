import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config/api_config.dart';
import '../core/theme/app_theme.dart';
import '../models/listing.dart';
import '../state/locale_provider.dart';
import 'app_back_button.dart';
import 'app_chip.dart';
import 'app_icon_badge.dart';
import 'manager_chat/ask_manager_button.dart';
import 'network_image_box.dart';

/// The shared "top of a listing detail page" — photo gallery hero, swipe
/// gallery + thumbnail strip, category/title/rating/city/phone, and
/// (optionally) the description block. Used by both `ServiceDetailScreen`
/// (every non-restaurant category) and `RestaurantDetailScreen` (brief
/// section 1: "переиспользуй gallery/title/description/rating/... из
/// service_detail_screen.dart, не дублируй весь экран"), so this exact
/// header never has two separate implementations drifting apart.
///
/// Returns a list of slivers — the caller's own `CustomScrollView` spreads
/// this in and appends whatever screen-specific slivers come after.
List<Widget> listingHeroSlivers({
  required BuildContext context,
  required Listing listing,
  required AppLocale locale,
  required PageController pageController,
  required int activeImage,
  required ValueChanged<int> onPageChanged,
  required ValueChanged<int> onThumbnailTap,
  bool includeDescription = true,
}) {
  final images = listing.imageUrls;
  final categoryLabel = listing.category?.name(locale);

  return [
    SliverAppBar(
      pinned: true,
      expandedHeight: 260,
      backgroundColor: context.mereytoiColors.backgroundPrimary,
      leading: const Padding(
        padding: EdgeInsets.only(left: AppSpacing.xs),
        child: AppBackButton(onHero: true),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: images.isEmpty
            ? const NetworkImageBox(
                url: null,
                borderRadius: 0,
                fallbackIcon: Icons.celebration_outlined,
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  PageView.builder(
                    controller: pageController,
                    onPageChanged: onPageChanged,
                    itemCount: images.length,
                    itemBuilder: (context, i) => NetworkImageBox(
                      url: ApiConfig.mediaUrl(images[i]),
                      borderRadius: 0,
                      fallbackIcon: Icons.celebration_outlined,
                    ),
                  ),
                  if (images.length > 1)
                    Positioned(
                      top: AppSpacing.md,
                      right: AppSpacing.md,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(AppRadius.chip),
                        ),
                        child: Text(
                          '${activeImage + 1} / ${images.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    ),
    SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        // `Builder` (not the outer widget's own context) so `Theme.of`
        // below reads the real inherited theme regardless of where this
        // sliver list gets spread into.
        child: Builder(
          builder: (context) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (images.length > 1) ...[
                SizedBox(
                  height: 48,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: images.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: AppSpacing.xs),
                    itemBuilder: (context, i) => GestureDetector(
                      onTap: () => onThumbnailTap(i),
                      child: Container(
                        width: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          border: Border.all(
                            color: i == activeImage
                                ? context.mereytoiColors.goldPrimary
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: NetworkImageBox(
                          url: ApiConfig.mediaUrl(images[i]),
                          borderRadius: 0,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (categoryLabel != null && categoryLabel.isNotEmpty)
                Text(
                  categoryLabel.toUpperCase(),
                  style: TextStyle(
                    color: context.mereytoiColors.goldPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                listing.name(locale),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontSize: 19),
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xxs,
                runSpacing: AppSpacing.xxs,
                children: [
                  if (listing.city.isNotEmpty)
                    AppMetaChip(
                      icon: Icons.place_outlined,
                      label: listing.city,
                    ),
                  if (listing.rating > 0)
                    AppMetaChip(
                      icon: Icons.star_rounded,
                      label: listing.rating.toStringAsFixed(1),
                      iconColor: context.mereytoiColors.goldPrimary,
                    ),
                  if (listing.phone.isNotEmpty)
                    AppMetaChip(
                      icon: Icons.call_outlined,
                      label: listing.phone,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: AskManagerButton(listing: listing, locale: locale),
              ),
              if (includeDescription &&
                  listing.description(locale).isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  t(locale, ru: 'Описание', kz: 'Сипаттама'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                ListingDescriptionText(
                  text: listing.description(locale),
                  locale: locale,
                ),
              ],
              // Same content ServiceDetail.jsx's own "Видео" section shows
              // (frontend renders a native `<video controls>` per URL) —
              // opened externally here rather than embedded, so this stays
              // a `url_launcher` call (already a dependency everywhere
              // else in this app) instead of pulling in a full video-
              // playback package for something that can't be verified on
              // a real device this session anyway.
              if (listing.videoUrls.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  t(locale, ru: 'Видео', kz: 'Видео'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                for (final url in listing.videoUrls) ...[
                  _VideoLinkTile(url: url, locale: locale),
                  const SizedBox(height: AppSpacing.xs),
                ],
              ],
            ],
          ),
        ),
      ),
    ),
  ];
}

/// A description that never becomes "one giant wall of text": collapses
/// past a few lines with a "Показать полностью" / "Свернуть" toggle.
/// Presentation-only — the underlying `listing.description` is untouched.
class ListingDescriptionText extends StatefulWidget {
  const ListingDescriptionText({
    super.key,
    required this.text,
    required this.locale,
  });

  final String text;
  final AppLocale locale;

  static const _collapsedLines = 4;
  static const _longThreshold = 180;

  @override
  State<ListingDescriptionText> createState() => _ListingDescriptionTextState();
}

class _ListingDescriptionTextState extends State<ListingDescriptionText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isLong = widget.text.length > ListingDescriptionText._longThreshold;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.text,
          maxLines: _expanded || !isLong
              ? null
              : ListingDescriptionText._collapsedLines,
          overflow: _expanded || !isLong
              ? TextOverflow.visible
              : TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.55),
        ),
        if (isLong)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
                minimumSize: const Size(0, 44),
              ),
              child: Text(
                _expanded
                    ? t(widget.locale, ru: 'Свернуть', kz: 'Жию')
                    : t(
                        widget.locale,
                        ru: 'Показать полностью',
                        kz: 'Толығырақ көрсету',
                      ),
              ),
            ),
          ),
      ],
    );
  }
}

/// One row for a listing's video (brief section 2 — "видео"): a play icon
/// + label that opens the file in the device's own video player/browser,
/// same destination `ApiConfig.mediaUrl` already resolves images to.
class _VideoLinkTile extends StatelessWidget {
  const _VideoLinkTile({required this.url, required this.locale});

  final String url;
  final AppLocale locale;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.mereytoiColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => launchUrl(
          Uri.parse(ApiConfig.mediaUrl(url)),
          mode: LaunchMode.externalApplication,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              AppIconBadge(
                icon: Icons.play_arrow_rounded,
                size: 40,
                iconSize: 22,
                background: context.mereytoiColors.surfaceSoft,
                iconColor: context.mereytoiColors.goldPrimary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  t(locale, ru: 'Смотреть видео', kz: 'Видеоны көру'),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              Icon(
                Icons.open_in_new_rounded,
                size: 16,
                color: context.mereytoiColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
