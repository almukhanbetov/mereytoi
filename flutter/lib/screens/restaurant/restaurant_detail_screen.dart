import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../core/utils/format.dart';
import '../../domain/restaurant/restaurant_guest_bounds.dart';
import '../../domain/restaurant/restaurant_menu_filter.dart';
import '../../domain/restaurant/restaurant_price_calculator.dart';
import '../../models/cart_item.dart';
import '../../models/listing.dart';
import '../../models/listing_hall.dart';
import '../../models/listing_menu.dart';
import '../../models/listing_menu_extra.dart';
import '../../models/restaurant_selection.dart';
import '../../state/cart_provider.dart';
import '../../state/listings_provider.dart';
import '../../state/locale_provider.dart';
import '../../widgets/animated_price_text.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_error_view.dart';
import '../../widgets/app_loader.dart';
import '../../widgets/events/add_to_event_sheet.dart';
import '../../widgets/listing_hero_header.dart';
import '../../widgets/restaurant/extras_list.dart';
import '../../widgets/restaurant/guest_selector.dart';
import '../../widgets/restaurant/hall_selector.dart';
import '../../widgets/restaurant/menu_content_accordion.dart';
import '../../widgets/restaurant/menu_selector.dart';
import '../../widgets/restaurant/price_summary_card.dart';
import '../../widgets/restaurant/restaurant_location_card.dart';
import '../../widgets/restaurant/selection_progress_bar.dart';

/// A plain null-safe "find by id" — used instead of `package:collection`'s
/// `firstOrNull` (only a transitive dependency here, not declared directly
/// in pubspec.yaml) so this file doesn't depend on an undeclared package.
T? _findById<T>(List<T> items, int? id, int Function(T) idOf) {
  if (id == null) return null;
  for (final item in items) {
    if (idOf(item) == id) return item;
  }
  return null;
}

/// Brief section 1 — the restaurant/venue counterpart of
/// `ServiceDetailScreen`, used only when `listing.category?.slug ==
/// 'venues'`. Reuses the shared gallery/title/description/rating header
/// (`listingHeroSlivers`) rather than duplicating it, then adds the parts
/// that only make sense for a venue: hall picker, menu picker, menu
/// content accordion, guest count, extras, a price breakdown, and location
/// — ending in a sticky CTA that builds a [RestaurantSelection] (Stage-3
/// prep only; this stage never touches `CartItem`/`CartNotifier`).
class RestaurantDetailScreen extends ConsumerStatefulWidget {
  const RestaurantDetailScreen({super.key, required this.listingId});

  final int listingId;

  @override
  ConsumerState<RestaurantDetailScreen> createState() =>
      _RestaurantDetailScreenState();
}

class _RestaurantDetailScreenState
    extends ConsumerState<RestaurantDetailScreen> {
  final _pageController = PageController();
  int _activeImage = 0;

  int? _selectedHallId;
  int? _selectedMenuId;
  int? _guests;
  final Set<int> _selectedExtraIds = {};

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

  void _selectHall(ListingHall hall) {
    setState(() {
      _selectedHallId = hall.id;
      // Changing hall may change which menus are in scope — the previous
      // menu/extras/guest choice may no longer apply, so this starts fresh
      // rather than silently keeping a now-invalid selection.
      _selectedMenuId = null;
      _guests = null;
      _selectedExtraIds.clear();
    });
  }

  void _selectMenu(ListingMenu menu) {
    setState(() {
      _selectedMenuId = menu.id;
      _guests = null;
      _selectedExtraIds.clear();
    });
  }

  void _toggleExtra(ListingMenuExtra extra) {
    setState(() {
      if (_selectedExtraIds.contains(extra.id)) {
        _selectedExtraIds.remove(extra.id);
      } else {
        _selectedExtraIds.add(extra.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final listingAsync = ref.watch(listingDetailProvider(widget.listingId));
    final hallsAsync = ref.watch(listingHallsProvider(widget.listingId));
    final menusAsync = ref.watch(listingMenusProvider(widget.listingId));

    return Scaffold(
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
        data: (listing) => _RestaurantBody(
          listing: listing,
          locale: locale,
          pageController: _pageController,
          activeImage: _activeImage,
          onPageChanged: (i) => setState(() => _activeImage = i),
          onThumbnailTap: _goToImage,
          hallsAsync: hallsAsync,
          menusAsync: menusAsync,
          selectedHallId: _selectedHallId,
          selectedMenuId: _selectedMenuId,
          guestsOverride: _guests,
          selectedExtraIds: _selectedExtraIds,
          onSelectHall: _selectHall,
          onSelectMenu: _selectMenu,
          onGuestsChanged: (g) => setState(() => _guests = g),
          onToggleExtra: _toggleExtra,
        ),
      ),
      bottomNavigationBar: listingAsync.maybeWhen(
        data: (listing) {
          final allMenus = menusAsync.valueOrNull;
          if (allMenus == null) return const SizedBox.shrink();

          final menus = menusForHall(
            sortedActiveMenus(allMenus),
            _selectedHallId,
          );
          final menu =
              _findById(menus, _selectedMenuId, (m) => m.id) ??
              (menus.length == 1 ? menus.first : null);
          if (menu == null) return const SizedBox.shrink();

          final bounds = resolveGuestBounds(menu: menu, listing: listing);
          final guests = (_guests ?? bounds.min).clamp(
            bounds.min,
            bounds.max ?? (1 << 30),
          );
          final selectedExtras = menu.extras
              .where((e) => _selectedExtraIds.contains(e.id))
              .toList();
          final breakdown = RestaurantPriceCalculator.calculate(
            pricePerGuest: menu.pricePerGuest,
            guests: guests,
            selectedExtras: selectedExtras,
          );
          final halls = hallsAsync.valueOrNull;
          final hall = halls == null
              ? null
              : _findById(activeHalls(halls), _selectedHallId, (h) => h.id);

          return _StickyRestaurantCta(
            listing: listing,
            hall: hall,
            menu: menu,
            guests: guests,
            breakdown: breakdown,
            selectedExtrasCount: selectedExtras.length,
            locale: locale,
          );
        },
        orElse: () => null,
      ),
    );
  }
}

class _RestaurantBody extends ConsumerWidget {
  const _RestaurantBody({
    required this.listing,
    required this.locale,
    required this.pageController,
    required this.activeImage,
    required this.onPageChanged,
    required this.onThumbnailTap,
    required this.hallsAsync,
    required this.menusAsync,
    required this.selectedHallId,
    required this.selectedMenuId,
    required this.guestsOverride,
    required this.selectedExtraIds,
    required this.onSelectHall,
    required this.onSelectMenu,
    required this.onGuestsChanged,
    required this.onToggleExtra,
  });

  final Listing listing;
  final AppLocale locale;
  final PageController pageController;
  final int activeImage;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onThumbnailTap;
  final AsyncValue<List<ListingHall>> hallsAsync;
  final AsyncValue<List<ListingMenu>> menusAsync;
  final int? selectedHallId;
  final int? selectedMenuId;
  final int? guestsOverride;
  final Set<int> selectedExtraIds;
  final ValueChanged<ListingHall> onSelectHall;
  final ValueChanged<ListingMenu> onSelectMenu;
  final ValueChanged<int> onGuestsChanged;
  final ValueChanged<ListingMenuExtra> onToggleExtra;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Cheap, read-only lookups (never the source of truth for the actual
    // selection logic further down, which stays untouched) purely to
    // drive the progress strip's "done/pending" state and labels.
    final allHallsForProgress = hallsAsync.valueOrNull;
    final activeHallsForProgress = allHallsForProgress == null
        ? null
        : activeHalls(allHallsForProgress);
    final selectedHallForProgress = activeHallsForProgress == null
        ? null
        : _findById(activeHallsForProgress, selectedHallId, (h) => h.id);
    final allMenusForProgress = menusAsync.valueOrNull;
    final menusInScopeForProgress = allMenusForProgress == null
        ? null
        : menusForHall(sortedActiveMenus(allMenusForProgress), selectedHallId);
    final resolvedMenuForProgress = menusInScopeForProgress == null
        ? null
        : (_findById(menusInScopeForProgress, selectedMenuId, (m) => m.id) ??
              (menusInScopeForProgress.length == 1
                  ? menusInScopeForProgress.first
                  : null));
    final guestsForProgress = resolvedMenuForProgress == null
        ? null
        : (guestsOverride ??
              resolveGuestBounds(
                menu: resolvedMenuForProgress,
                listing: listing,
              ).min);
    // Same "is there a real number at all" gate the sticky CTA uses —
    // a menu priced "по запросу" (pricePerGuest == 0) never gets an
    // estimated total to hand the manager either.
    final estimatedTotalForChat =
        resolvedMenuForProgress != null &&
            resolvedMenuForProgress.pricePerGuest > 0 &&
            guestsForProgress != null
        ? RestaurantPriceCalculator.calculate(
            pricePerGuest: resolvedMenuForProgress.pricePerGuest,
            guests: guestsForProgress,
            selectedExtras: resolvedMenuForProgress.extras
                .where((e) => selectedExtraIds.contains(e.id))
                .toList(),
          ).estimatedTotal
        : null;

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
          chatHallName: selectedHallForProgress?.name(locale),
          chatMenuName: resolvedMenuForProgress?.name(locale),
          chatMenuPricePerGuest: resolvedMenuForProgress?.pricePerGuest,
          chatGuestCount: guestsForProgress,
          chatEstimatedTotal: estimatedTotalForChat,
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: SelectionProgressBar(
                    locale: locale,
                    hasHalls: activeHallsForProgress?.isNotEmpty ?? false,
                    selectedHall: selectedHallForProgress,
                    selectedMenu: resolvedMenuForProgress,
                    guests: guestsForProgress,
                    extrasCount: selectedExtraIds.length,
                    hasPrice: (resolvedMenuForProgress?.pricePerGuest ?? 0) > 0,
                  ),
                ),
                _SectionTitle(
                  t(locale, ru: 'Залы', kz: 'Залдар', en: 'Halls'),
                  icon: Icons.meeting_room_outlined,
                ),
                hallsAsync.when(
                  loading: () => const _HorizontalSkeleton(),
                  error: (err, _) => Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    child: AppErrorView(
                      message: apiErrorMessage(locale, err),
                      locale: locale,
                      onRetry: () =>
                          ref.invalidate(listingHallsProvider(listing.id)),
                    ),
                  ),
                  data: (allHalls) {
                    final halls = activeHalls(allHalls);
                    if (halls.isEmpty) {
                      return _EmptyHint(
                        text: t(
                          locale,
                          ru: 'Залы пока не добавлены',
                          kz: 'Залдар әлі қосылмаған',
                          en: 'No halls added yet',
                        ),
                      );
                    }
                    // Brief section 2 — auto-select when there's exactly one.
                    if (halls.length == 1 && selectedHallId == null) {
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => onSelectHall(halls.first),
                      );
                    }
                    final selectedHall = _findById(
                      halls,
                      selectedHallId,
                      (h) => h.id,
                    );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        HallSelector(
                          halls: halls,
                          selectedHallId: selectedHallId,
                          locale: locale,
                          onSelect: onSelectHall,
                        ),
                        if (selectedHall != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.lg,
                              AppSpacing.sm,
                              AppSpacing.lg,
                              0,
                            ),
                            child: _SelectedLine(
                              text: t(
                                locale,
                                ru: 'Выбран зал: ${selectedHall.name(locale)}',
                                kz: 'Таңдалды: ${selectedHall.name(locale)}',
                                en: 'Selected hall: ${selectedHall.name(locale)}',
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.xl),
                _SectionTitle(
                  t(locale, ru: 'Меню', kz: 'Мәзір', en: 'Menu'),
                  icon: Icons.restaurant_menu_outlined,
                ),
                menusAsync.when(
                  loading: () => const _HorizontalSkeleton(),
                  error: (err, _) => Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    child: AppErrorView(
                      message: apiErrorMessage(locale, err),
                      locale: locale,
                      onRetry: () =>
                          ref.invalidate(listingMenusProvider(listing.id)),
                    ),
                  ),
                  data: (rawMenus) {
                    final menus = menusForHall(
                      sortedActiveMenus(rawMenus),
                      selectedHallId,
                    );
                    if (menus.isEmpty) {
                      return _EmptyHint(
                        text: t(
                          locale,
                          ru: 'Меню пока не добавлены',
                          kz: 'Мәзірлер әлі қосылмаған',
                          en: 'No menus added yet',
                        ),
                      );
                    }
                    if (menus.length == 1 && selectedMenuId == null) {
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => onSelectMenu(menus.first),
                      );
                    }
                    final menu = _findById(menus, selectedMenuId, (m) => m.id);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MenuSelector(
                          menus: menus,
                          selectedMenuId: selectedMenuId,
                          locale: locale,
                          onSelect: onSelectMenu,
                        ),
                        if (menu != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.lg,
                              AppSpacing.lg,
                              AppSpacing.lg,
                              0,
                            ),
                            child: _MenuDetail(
                              listing: listing,
                              menu: menu,
                              locale: locale,
                              guestsOverride: guestsOverride,
                              selectedExtraIds: selectedExtraIds,
                              onGuestsChanged: onGuestsChanged,
                              onToggleExtra: onToggleExtra,
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.xl),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: RestaurantLocationCard(
                    listing: listing,
                    locale: locale,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MenuDetail extends StatelessWidget {
  const _MenuDetail({
    required this.listing,
    required this.menu,
    required this.locale,
    required this.guestsOverride,
    required this.selectedExtraIds,
    required this.onGuestsChanged,
    required this.onToggleExtra,
  });

  final Listing listing;
  final ListingMenu menu;
  final AppLocale locale;
  final int? guestsOverride;
  final Set<int> selectedExtraIds;
  final ValueChanged<int> onGuestsChanged;
  final ValueChanged<ListingMenuExtra> onToggleExtra;

  @override
  Widget build(BuildContext context) {
    final bounds = resolveGuestBounds(menu: menu, listing: listing);
    final guests = (guestsOverride ?? bounds.min).clamp(
      bounds.min,
      bounds.max ?? (1 << 30),
    );
    final selectedExtras = menu.extras
        .where((e) => selectedExtraIds.contains(e.id))
        .toList();
    final breakdown = RestaurantPriceCalculator.calculate(
      pricePerGuest: menu.pricePerGuest,
      guests: guests,
      selectedExtras: selectedExtras,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Этап 10Б-1А, requirement 4 — "выбранное меню" as its own
        // visible line, distinct from the picker cards above (which stop
        // showing the gold selected-border once the user scrolls past
        // them).
        _SelectedLine(
          text: t(
            locale,
            ru: 'Выбрано: ${menu.name(locale)}',
            kz: 'Таңдалды: ${menu.name(locale)}',
            en: 'Selected: ${menu.name(locale)}',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        MenuContentAccordion(sections: menu.sections, locale: locale),
        if (menu.sections.isNotEmpty) const SizedBox(height: AppSpacing.lg),
        AppCard(
          child: GuestSelector(
            guests: guests,
            bounds: bounds,
            locale: locale,
            onChanged: onGuestsChanged,
          ),
        ),
        if (menu.extras.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: ExtrasList(
              extras: menu.extras,
              selectedIds: selectedExtraIds,
              locale: locale,
              onToggle: onToggleExtra,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        PriceSummaryCard(
          pricePerGuest: menu.pricePerGuest,
          guests: guests,
          breakdown: breakdown,
          locale: locale,
        ),
      ],
    );
  }
}

class _StickyRestaurantCta extends ConsumerWidget {
  const _StickyRestaurantCta({
    required this.listing,
    required this.hall,
    required this.menu,
    required this.guests,
    required this.breakdown,
    required this.selectedExtrasCount,
    required this.locale,
  });

  final Listing listing;
  final ListingHall? hall;
  final ListingMenu menu;
  final int guests;
  final RestaurantPriceBreakdown breakdown;

  /// How many extras are currently selected — folded into the summary
  /// line below so "what's already chosen" (Этап 10Б-1, requirement 4) is
  /// visible from the one part of the screen that never scrolls away,
  /// without repeating each extra's full title here.
  final int selectedExtrasCount;
  final AppLocale locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasRealPrice = menu.pricePerGuest > 0;
    final summary = [
      if (hall != null) hall!.name(locale),
      menu.name(locale),
      '$guests ${t(locale, ru: "чел.", kz: "адам", en: "guests")}',
      if (selectedExtrasCount > 0)
        t(
          locale,
          ru: '+$selectedExtrasCount доп.',
          kz: '+$selectedExtrasCount қосымша',
          en: '+$selectedExtrasCount extra',
        ),
    ].join(' · ');

    return DecoratedBox(
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Row(
                children: [
                  Expanded(
                    child: AnimatedPriceText(
                      text: hasRealPrice
                          ? formatPrice(breakdown.estimatedTotal)
                          : t(
                              locale,
                              ru: 'По запросу',
                              kz: 'Сұрау бойынша',
                              en: 'On request',
                            ),
                      style: TextStyle(
                        color: context.mereytoiColors.goldSoft,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  // Brief section 10 — restaurant variant: full snapshot
                  // (hall/menu/guests/estimatedTotal) goes straight into the
                  // candidate, same identity the event workspace's own
                  // dedup — (listing_id, hall_id, menu_id) — expects.
                  Material(
                    color: context.mereytoiColors.surfaceSoft,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      onTap: () => openAddToEventSheet(
                        context,
                        listingId: listing.id,
                        hallId: hall?.id ?? menu.hallId,
                        menuId: menu.id,
                        guests: guests,
                        estimatedTotal: hasRealPrice
                            ? breakdown.estimatedTotal
                            : null,
                      ),
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
                        final selection = RestaurantSelection.fromBreakdown(
                          listingId: listing.id,
                          hallId: hall?.id ?? menu.hallId,
                          hallName: hall?.name(locale),
                          menuId: menu.id,
                          menuName: menu.name(locale),
                          menuPricePerGuest: menu.pricePerGuest,
                          guests: guests,
                          breakdown: breakdown,
                          locale: locale,
                        );
                        final item = CartItem.fromRestaurantSelection(
                          selection,
                          listingName: listing.name(locale),
                          categoryLabel: listing.category?.name(locale) ?? '',
                          image: listing.coverImage,
                        );
                        // Decide the toast text *before* writing — addItem
                        // itself doesn't report whether this was a fresh add or
                        // an update to an existing variant.
                        final alreadyInCart = ref
                            .read(cartProvider.notifier)
                            .containsKey(item.key);
                        ref.read(cartProvider.notifier).addItem(item);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              alreadyInCart
                                  ? t(
                                      locale,
                                      ru: 'Корзина обновлена',
                                      kz: 'Себет жаңартылды',
                                      en: 'Cart updated',
                                    )
                                  : t(
                                      locale,
                                      ru: 'Добавлено в корзину',
                                      kz: 'Себетке қосылды',
                                      en: 'Added to cart',
                                    ),
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.shopping_bag_outlined, size: 17),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          t(
                            locale,
                            ru: 'Добавить в корзину',
                            kz: 'Себетке қосу',
                            en: 'Add to cart',
                          ),
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

/// A single "here's what you picked" confirmation line — a gold check +
/// one line of ellipsized text. Shared by the hall and menu sections
/// (Этап 10Б-Б2 extracted this out of `_MenuDetail`, which had it inline,
/// when the hall section needed the exact same shape) so a user scanning
/// past either picker sees the same, already-familiar confirmation
/// pattern rather than two subtly different ones.
class _SelectedLine extends StatelessWidget {
  const _SelectedLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.check_circle_rounded,
          size: 16,
          color: context.mereytoiColors.goldPrimary,
        ),
        const SizedBox(width: AppSpacing.xxs),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.icon});

  final String text;

  /// Этап 10Б-1: a small leading glyph per section (matching the icon
  /// already used inside `HallSelector`/`MenuSelector`'s own cards) — a
  /// cheap, consistent visual anchor that makes each block easier to scan
  /// past at a glance, without literal "Шаг 1/2/3" labeling.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: context.mereytoiColors.goldPrimary),
            const SizedBox(width: AppSpacing.xxs),
          ],
          Text(text, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _HorizontalSkeleton extends StatelessWidget {
  const _HorizontalSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: SizedBox(
        height: 100,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.mereytoiColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}
