import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/api_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../core/utils/format.dart';
import '../../models/cart_item.dart';
import '../../models/listing.dart';
import '../../state/cart_provider.dart';
import '../../state/listings_provider.dart';
import '../../state/locale_provider.dart';
import '../../widgets/app_back_button.dart';
import '../../widgets/app_chip.dart';
import '../../widgets/app_error_view.dart';
import '../../widgets/app_loader.dart';
import '../../widgets/network_image_box.dart';

/// The mobile counterpart of frontend/src/components/services/ServiceDetail.jsx —
/// GET /api/listings/:id (the "detail endpoint" from the audit). Shows every
/// public field the API returns: images, name, category, description,
/// price, rating, city, phone — nothing admin-only.
///
/// Laid out as a product page: a large image hero + gallery, info in
/// distinct blocks (title/meta, description, guest count), and a CTA that's
/// genuinely pinned via `Scaffold.bottomNavigationBar` — it never scrolls
/// away, and it's the one place price + "Добавить в корзину" live.
class ServiceDetailScreen extends ConsumerStatefulWidget {
  const ServiceDetailScreen({super.key, required this.listingId});

  final int listingId;

  @override
  ConsumerState<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends ConsumerState<ServiceDetailScreen> {
  final _pageController = PageController();
  int _activeImage = 0;
  int _guests = 1;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToImage(int i) {
    setState(() => _activeImage = i);
    _pageController.animateToPage(i, duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final listingAsync = ref.watch(listingDetailProvider(widget.listingId));

    return Scaffold(
      // The "data" state builds its own app bar as part of the hero
      // `SliverAppBar` below — but loading/error never reach that sliver,
      // so without this they'd render with no back affordance at all (only
      // the OS back gesture, no on-screen control). A plain, compact bar
      // here keeps a real back button present in every state.
      appBar: listingAsync.maybeWhen(data: (_) => null, orElse: () => AppBar()),
      body: listingAsync.when(
        loading: () => const AppLoader(),
        error: (err, _) => Center(
          child: AppErrorView(
            message: apiErrorMessage(locale, err),
            locale: locale,
            onRetry: () => ref.invalidate(listingDetailProvider(widget.listingId)),
          ),
        ),
        data: (listing) => _DetailBody(
          listing: listing,
          locale: locale,
          pageController: _pageController,
          activeImage: _activeImage,
          onPageChanged: (i) => setState(() => _activeImage = i),
          onThumbnailTap: _goToImage,
        ),
      ),
      bottomNavigationBar: listingAsync.maybeWhen(
        data: (listing) => _StickyCta(
          listing: listing,
          locale: locale,
          guests: _guests,
          onGuestsChanged: (g) => setState(() => _guests = g),
        ),
        orElse: () => null,
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.listing,
    required this.locale,
    required this.pageController,
    required this.activeImage,
    required this.onPageChanged,
    required this.onThumbnailTap,
  });

  final Listing listing;
  final AppLocale locale;
  final PageController pageController;
  final int activeImage;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onThumbnailTap;

  @override
  Widget build(BuildContext context) {
    final images = listing.imageUrls;
    final categoryLabel = listing.category?.name(locale);

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 260,
          backgroundColor: AppColors.backgroundPrimary,
          // Explicit rather than the default `BackButton`: a plain icon can
          // get lost against a bright photo, so this sits on its own soft
          // dark circle instead. `SliverAppBar` already keeps `leading`
          // inside the safe area / above the status bar on its own.
          leading: const Padding(
            padding: EdgeInsets.only(left: AppSpacing.xs),
            child: AppBackButton(onHero: true),
          ),
          flexibleSpace: FlexibleSpaceBar(
            background: images.isEmpty
                ? const NetworkImageBox(url: null, borderRadius: 0, fallbackIcon: Icons.celebration_outlined)
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      // Swipeable, not just a static photo behind tappable
                      // thumbnails — the gallery gesture people already
                      // expect from a marketplace listing.
                      PageView.builder(
                        controller: pageController,
                        onPageChanged: onPageChanged,
                        itemCount: images.length,
                        itemBuilder: (context, i) => NetworkImageBox(url: ApiConfig.mediaUrl(images[i]), borderRadius: 0, fallbackIcon: Icons.celebration_outlined),
                      ),
                      if (images.length > 1)
                        Positioned(
                          top: AppSpacing.md,
                          right: AppSpacing.md,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 4),
                            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(AppRadius.chip)),
                            child: Text(
                              '${activeImage + 1} / ${images.length}',
                              style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (images.length > 1) ...[
                  SizedBox(
                    height: 48,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: images.length,
                      separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
                      itemBuilder: (context, i) => GestureDetector(
                        onTap: () => onThumbnailTap(i),
                        child: Container(
                          width: 48,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            border: Border.all(color: i == activeImage ? AppColors.goldPrimary : Colors.transparent, width: 2),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: NetworkImageBox(url: ApiConfig.mediaUrl(images[i]), borderRadius: 0),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                // ---- Block 1: identity ----
                if (categoryLabel != null && categoryLabel.isNotEmpty)
                  Text(categoryLabel.toUpperCase(), style: const TextStyle(color: AppColors.goldPrimary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  listing.name(locale),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 19),
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xxs,
                  runSpacing: AppSpacing.xxs,
                  children: [
                    if (listing.city.isNotEmpty) AppMetaChip(icon: Icons.place_outlined, label: listing.city),
                    if (listing.rating > 0) AppMetaChip(icon: Icons.star_rounded, label: listing.rating.toStringAsFixed(1), iconColor: AppColors.goldPrimary),
                    if (listing.phone.isNotEmpty) AppMetaChip(icon: Icons.call_outlined, label: listing.phone),
                  ],
                ),
                // ---- Block 2: description ----
                if (listing.description(locale).isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text(t(locale, ru: 'Описание', kz: 'Сипаттама'), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  _DescriptionText(text: listing.description(locale), locale: locale),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A description that never becomes "one giant wall of text": collapses
/// past a few lines with a "Показать полностью" / "Свернуть" toggle. This
/// is presentation-only — the underlying `listing.description` is untouched,
/// nothing about the data or the API response changes.
class _DescriptionText extends StatefulWidget {
  const _DescriptionText({required this.text, required this.locale});

  final String text;
  final AppLocale locale;

  static const _collapsedLines = 4;
  // A rough heuristic for "long enough that collapsing is worth it" — avoids
  // a TextPainter measurement pass just to decide whether to show the toggle.
  static const _longThreshold = 180;

  @override
  State<_DescriptionText> createState() => _DescriptionTextState();
}

class _DescriptionTextState extends State<_DescriptionText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isLong = widget.text.length > _DescriptionText._longThreshold;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.text,
          maxLines: _expanded || !isLong ? null : _DescriptionText._collapsedLines,
          overflow: _expanded || !isLong ? TextOverflow.visible : TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.55),
        ),
        if (isLong)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft, minimumSize: const Size(0, 44)),
              child: Text(
                _expanded ? t(widget.locale, ru: 'Свернуть', kz: 'Жию') : t(widget.locale, ru: 'Показать полностью', kz: 'Толығырақ көрсету'),
              ),
            ),
          ),
      ],
    );
  }
}

/// Pinned to the bottom of the screen (via `Scaffold.bottomNavigationBar`,
/// not part of the scroll view) — price, the guest stepper for per-person
/// listings, and the single "Добавить в корзину" action.
class _StickyCta extends ConsumerWidget {
  const _StickyCta({required this.listing, required this.locale, required this.guests, required this.onGuestsChanged});

  final Listing listing;
  final AppLocale locale;
  final int guests;
  final ValueChanged<int> onGuestsChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPerPerson = listing.isPerPerson;
    final total = isPerPerson ? guests * listing.price : listing.price;
    final inCart = ref.watch(cartProvider.select((items) => items.any((i) => i.listingId == listing.id)));
    final categoryLabel = listing.category?.name(locale);

    return DecoratedBox(
      // A hairline top edge reads as "lighter" than a heavy drop shadow while
      // still cleanly separating the bar from the scrolling content above it.
      decoration: const BoxDecoration(
        color: AppColors.surfaceElevated,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isPerPerson) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(t(locale, ru: 'Гостей', kz: 'Қонақтар'), style: Theme.of(context).textTheme.bodyMedium),
                    _GuestStepper(
                      guests: guests,
                      min: listing.minGuests == 0 ? 1 : listing.minGuests,
                      max: listing.maxGuests,
                      onChanged: onGuestsChanged,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
              Row(
                children: [
                  // Sized to its own content (not Expanded) — the price is
                  // short, so the button on the right gets the room it
                  // actually needs for a full, un-truncated label.
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isPerPerson ? '${formatPrice(listing.price)} / ${t(locale, ru: "чел.", kz: "адам")}' : t(locale, ru: 'Стоимость', kz: 'Құны'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(formatPrice(total), style: const TextStyle(color: AppColors.goldSoft, fontWeight: FontWeight.w700, fontSize: 18)),
                    ],
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      ),
                      onPressed: () {
                        final item = CartItem.fromListing(
                          listing,
                          name: listing.name(locale),
                          categoryLabel: categoryLabel ?? '',
                          guests: guests,
                        );
                        ref.read(cartProvider.notifier).addItem(item);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(t(locale, ru: 'Добавлено в корзину', kz: 'Себетке қосылды'))),
                        );
                      },
                      icon: Icon(inCart ? Icons.check_rounded : Icons.shopping_bag_outlined, size: 17),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(inCart ? t(locale, ru: 'Обновить', kz: 'Жаңарту') : t(locale, ru: 'В корзину', kz: 'Себетке')),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuestStepper extends StatelessWidget {
  const _GuestStepper({required this.guests, required this.min, required this.max, required this.onChanged});

  final int guests;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepButton(icon: Icons.remove_rounded, onTap: guests > min ? () => onChanged(guests - 1) : null),
        SizedBox(width: 36, child: Text('$guests', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium)),
        _StepButton(icon: Icons.add_rounded, onTap: (max == 0 || guests < max) ? () => onChanged(guests + 1) : null),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: enabled ? AppColors.surfaceSoft : AppColors.surface,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 17, color: enabled ? AppColors.goldPrimary : AppColors.textMuted),
        ),
      ),
    );
  }
}
