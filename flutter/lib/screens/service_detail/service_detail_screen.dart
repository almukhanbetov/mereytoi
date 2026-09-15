import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../core/utils/format.dart';
import '../../models/cart_item.dart';
import '../../models/listing.dart';
import '../../state/cart_provider.dart';
import '../../state/listings_provider.dart';
import '../../state/locale_provider.dart';
import '../../widgets/app_error_view.dart';
import '../../widgets/app_loader.dart';
import '../../widgets/events/add_to_event_sheet.dart';
import '../../widgets/listing_hero_header.dart';

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
  ConsumerState<ServiceDetailScreen> createState() =>
      _ServiceDetailScreenState();
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
    _pageController.animateToPage(
      i,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
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
            onRetry: () =>
                ref.invalidate(listingDetailProvider(widget.listingId)),
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
    return CustomScrollView(
      slivers: [
        ...listingHeroSlivers(
          context: context,
          listing: listing,
          locale: locale,
          pageController: pageController,
          activeImage: activeImage,
          onPageChanged: onPageChanged,
          onThumbnailTap: onThumbnailTap,
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
      ],
    );
  }
}

/// Pinned to the bottom of the screen (via `Scaffold.bottomNavigationBar`,
/// not part of the scroll view) — price, the guest stepper for per-person
/// listings, and the single "Добавить в корзину" action.
class _StickyCta extends ConsumerWidget {
  const _StickyCta({
    required this.listing,
    required this.locale,
    required this.guests,
    required this.onGuestsChanged,
  });

  final Listing listing;
  final AppLocale locale;
  final int guests;
  final ValueChanged<int> onGuestsChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPerPerson = listing.isPerPerson;
    final total = isPerPerson ? guests * listing.price : listing.price;
    final inCart = ref.watch(
      cartProvider.select(
        (items) => items.any((i) => i.listingId == listing.id),
      ),
    );
    final categoryLabel = listing.category?.name(locale);

    return DecoratedBox(
      // A hairline top edge reads as "lighter" than a heavy drop shadow while
      // still cleanly separating the bar from the scrolling content above it.
      decoration: BoxDecoration(
        color: context.mereytoiColors.surfaceElevated,
        border: Border(top: BorderSide(color: context.mereytoiColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isPerPerson) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      t(locale, ru: 'Гостей', kz: 'Қонақтар'),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
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
                        isPerPerson
                            ? '${formatPrice(listing.price)} / ${t(locale, ru: "чел.", kz: "адам")}'
                            : t(locale, ru: 'Стоимость', kz: 'Құны'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        formatPrice(total),
                        style: TextStyle(
                          color: context.mereytoiColors.goldSoft,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  // Brief section 10 — "Добавить в мой той": an icon-only
                  // button here keeps the row compact (cart stays the
                  // primary action); it opens the same event-picker sheet
                  // a restaurant listing's own sticky CTA uses, just with
                  // no hall/menu/guests/estimatedTotal variant data (see
                  // AddToEventMenu.jsx's own "undefined for an ordinary
                  // service" — no invented per-guest total for one).
                  Material(
                    color: context.mereytoiColors.surfaceSoft,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      onTap: () =>
                          openAddToEventSheet(context, listingId: listing.id),
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Icon(
                          Icons.celebration_outlined,
                          size: 19,
                          color: context.mereytoiColors.goldPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                        ),
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
                          SnackBar(
                            content: Text(
                              t(
                                locale,
                                ru: 'Добавлено в корзину',
                                kz: 'Себетке қосылды',
                              ),
                            ),
                          ),
                        );
                      },
                      icon: Icon(
                        inCart
                            ? Icons.check_rounded
                            : Icons.shopping_bag_outlined,
                        size: 17,
                      ),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          inCart
                              ? t(locale, ru: 'Обновить', kz: 'Жаңарту')
                              : t(locale, ru: 'В корзину', kz: 'Себетке'),
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
    );
  }
}

class _GuestStepper extends StatelessWidget {
  const _GuestStepper({
    required this.guests,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final int guests;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepButton(
          icon: Icons.remove_rounded,
          onTap: guests > min ? () => onChanged(guests - 1) : null,
        ),
        SizedBox(
          width: 36,
          child: Text(
            '$guests',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        _StepButton(
          icon: Icons.add_rounded,
          onTap: (max == 0 || guests < max)
              ? () => onChanged(guests + 1)
              : null,
        ),
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
      color: enabled
          ? context.mereytoiColors.surfaceSoft
          : context.mereytoiColors.surface,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            icon,
            size: 17,
            color: enabled
                ? context.mereytoiColors.goldPrimary
                : context.mereytoiColors.textMuted,
          ),
        ),
      ),
    );
  }
}
