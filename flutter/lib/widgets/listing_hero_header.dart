import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config/api_config.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/whatsapp.dart';
import '../models/listing.dart';
import '../screens/provider/provider_profile_screen.dart';
import '../state/locale_provider.dart';
import 'app_back_button.dart';
import 'app_chip.dart';
import 'app_icon_badge.dart';
import 'manager_chat/ask_manager_button.dart';
import 'network_image_box.dart';
import 'photo_viewer_screen.dart';
import 'provider_chat/message_provider_button.dart';

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
  // Этап 10Б-53 — the restaurant calculator's current selection, passed
  // straight through to `AskManagerButton` so "Спросить менеджера" carries
  // the actual hall/menu/guests/total the customer is looking at, not
  // just the listing. `ServiceDetailScreen` never passes these.
  String? chatHallName,
  String? chatMenuName,
  int? chatMenuPricePerGuest,
  int? chatGuestCount,
  int? chatEstimatedTotal,
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
                    itemBuilder: (context, i) => GestureDetector(
                      onTap: () => PhotoViewerScreen.open(
                        context,
                        imageUrls: images,
                        initialIndex: i,
                      ),
                      child: NetworkImageBox(
                        url: ApiConfig.mediaUrl(images[i]),
                        borderRadius: 0,
                        fallbackIcon: Icons.celebration_outlined,
                      ),
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
                  Positioned(
                    bottom: AppSpacing.md,
                    right: AppSpacing.md,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.zoom_out_map_rounded,
                          color: Colors.white,
                          size: 16,
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
                child: AskManagerButton(
                  listing: listing,
                  locale: locale,
                  hallName: chatHallName,
                  menuName: chatMenuName,
                  menuPricePerGuest: chatMenuPricePerGuest,
                  guestCount: chatGuestCount,
                  estimatedTotal: chatEstimatedTotal,
                ),
              ),
              // Этап 11 "Provider Marketplace" (Этап 11E QA finding: this
              // was missing from the Flutter side entirely — the model
              // parsed `provider` but no screen ever rendered it). Null
              // for every listing with no self-serve provider owner.
              if (listing.provider != null) ...[
                const SizedBox(height: AppSpacing.sm),
                _ProviderBlock(
                  provider: listing.provider!,
                  listing: listing,
                  locale: locale,
                ),
              ],
              if (includeDescription &&
                  listing.description(locale).isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  t(locale, ru: 'Описание', kz: 'Сипаттама', en: 'Description'),
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
                  t(locale, ru: 'Видео', kz: 'Видео', en: 'Video'),
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
                    ? t(
                        widget.locale,
                        ru: 'Свернуть',
                        kz: 'Жию',
                        en: 'Collapse',
                      )
                    : t(
                        widget.locale,
                        ru: 'Показать полностью',
                        kz: 'Толығырақ көрсету',
                        en: 'Show more',
                      ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Этап 11 brief section 9: name/avatar/city + a contact button.
/// Deliberately NOT `AskManagerButton` above (that's a real chat with
/// MEREYTOI's own manager) — a direct WhatsApp/Telegram/phone link to the
/// service's own provider, since no provider<->client chat backend exists
/// this stage. Mirrors frontend/src/components/services/ServiceDetail.jsx's
/// own ProviderBlock.
class _ProviderBlock extends StatelessWidget {
  const _ProviderBlock({
    required this.provider,
    required this.listing,
    required this.locale,
  });

  final ListingProviderBrief provider;
  final Listing listing;
  final AppLocale locale;

  Uri? get _contactUri {
    final waDigits = toWhatsAppDigits(provider.whatsapp ?? '');
    if (waDigits.isNotEmpty) return Uri.parse('https://wa.me/$waDigits');
    final telegram = provider.telegram;
    if (telegram != null && telegram.isNotEmpty) {
      return Uri.parse('https://t.me/${telegram.replaceFirst('@', '')}');
    }
    final phone = provider.phone;
    if (phone != null && phone.isNotEmpty) {
      return Uri.parse('tel:${phone.replaceAll(' ', '')}');
    }
    return null;
  }

  /// Этап 11G brief section 1 — name/avatar open the public
  /// ProviderProfileScreen. `provider.id` is always present for any
  /// provider a listing actually has (see providerDetailOut's own doc
  /// comment on the backend) — never 0 in practice, but a listing that
  /// somehow predates the id field simply doesn't navigate rather than
  /// opening a broken profile.
  void _openProfile(BuildContext context) {
    if (provider.id == 0) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProviderProfileScreen(providerId: provider.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    final contactUri = _contactUri;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            onTap: () => _openProfile(context),
            child: Row(
              children: [
                if (provider.avatarUrl != null &&
                    provider.avatarUrl!.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: NetworkImageBox(
                        url: ApiConfig.mediaUrl(provider.avatarUrl),
                        borderRadius: 0,
                      ),
                    ),
                  )
                else
                  const AppIconBadge(icon: Icons.storefront_outlined, size: 44),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        t(
                          locale,
                          ru: 'Услугодатель',
                          kz: 'Қызмет көрсетуші',
                          en: 'Provider',
                        ),
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: .4,
                          color: colors.goldPrimary,
                        ),
                      ),
                      Text(
                        provider.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (provider.city != null && provider.city!.isNotEmpty)
                        Text(
                          provider.city!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: colors.textMuted,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            children: [
              if (provider.id != 0)
                MessageProviderButton(
                  providerId: provider.id,
                  providerName: provider.displayName,
                  providerAvatarUrl: provider.avatarUrl,
                  listingId: listing.id,
                  listingName: listing.name(locale),
                  listingPrice: listing.price,
                  locale: locale,
                ),
              if (contactUri != null)
                TextButton(
                  onPressed: () => launchUrl(
                    contactUri,
                    mode: LaunchMode.externalApplication,
                  ),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 36),
                  ),
                  child: Text(
                    t(
                      locale,
                      ru: 'Связаться →',
                      kz: 'Байланысу →',
                      en: 'Contact →',
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
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
                  t(
                    locale,
                    ru: 'Смотреть видео',
                    kz: 'Видеоны көру',
                    en: 'Watch video',
                  ),
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
