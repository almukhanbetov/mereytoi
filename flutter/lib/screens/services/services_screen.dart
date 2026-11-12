import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../core/utils/listing_navigation.dart';
import '../../state/categories_provider.dart';
import '../../state/promotion_provider.dart';
import '../../state/locale_provider.dart';
import '../../widgets/chat/chat_fab.dart';
import '../../widgets/app_back_button.dart';
import '../../widgets/app_error_view.dart';
import '../../widgets/app_icon_badge.dart';
import '../../widgets/app_skeleton.dart';
import '../../widgets/fade_slide_in.dart';
import '../../widgets/promotion/ad_impression_tracker.dart';
import '../../widgets/service_card.dart';
import '../../widgets/services/services_category_grid.dart';
import '../../widgets/services/services_city_selector.dart';
import '../../widgets/services/services_style.dart';

/// The mobile counterpart of the site's /services catalog
/// (frontend/src/components/services/ServicesClient.jsx): a city card, a
/// search field and a category grid above a list of listings, all backed by
/// the *same*
/// `GET /api/listings?category=<slug>&search=<term>` the Go handler
/// already supports server-side — no client-only filtering invented here.
///
/// Without [initialCategorySlug] this is the whole catalog: a tile opens that
/// category as its own pushed copy of this screen, so the catalog below keeps
/// its scroll position and search. With a slug it shows only that category,
/// titled with its name.
///
/// Results are a 2-column grid of [ServiceGridCard]s, marketplace style.
/// Names vary a lot in length, so every card reserves two lines for the
/// name and the grid gives all cards one computed height.
class ServicesScreen extends ConsumerStatefulWidget {
  const ServicesScreen({super.key, this.initialCategorySlug});

  /// Non-null when showing one category, matching the site's
  /// `/services?category=<slug>` deep link.
  final String? initialCategorySlug;

  @override
  ConsumerState<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends ConsumerState<ServicesScreen> {
  final _searchController = TextEditingController();
  String _search = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _search = value.trim());
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    setState(() => _search = '');
  }

  void _openCategory(String slug) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ServicesScreen(initialCategorySlug: slug),
      ),
    );
  }

  /// Results of the current query: skeleton, error, empty state or the
  /// grid. Pages load as the end comes near; ads arrive already in place.
  List<Widget> _resultSlivers(
    BuildContext context,
    AppLocale locale,
    CatalogQuery query,
    CatalogFeedState feed,
  ) {
    if (feed.loading) {
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.xl,
          ),
          // The same 2-column geometry as the loaded grid, so the first
          // load doesn't flash a one-per-row list.
          sliver: SliverLayoutBuilder(
            builder: (context, constraints) => SliverGrid.builder(
              gridDelegate: _gridDelegate(context, constraints.crossAxisExtent),
              itemCount: 6,
              itemBuilder: (context, i) => const AppSkeleton(borderRadius: 16),
            ),
          ),
        ),
      ];
    }
    if (feed.error != null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: AppErrorView(
            message: apiErrorMessage(locale, feed.error!),
            error: feed.error!,
            locale: locale,
            // A failed connection usually failed the category grid too:
            // retry both, so the catalog doesn't stay half empty.
            onRetry: () {
              ref.invalidate(categoriesProvider);
              ref.read(catalogFeedProvider(query).notifier).reload();
            },
          ),
        ),
      ];
    }
    final items = feed.items;
    if (items.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _EmptyResults(
            locale: locale,
            showReset: _search.isNotEmpty,
            onReset: _clearSearch,
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        sliver: SliverToBoxAdapter(
          child: _SectionTitle(
            t(
              locale,
              ru: 'Найдено: ${feed.total}',
              kz: 'Табылды: ${feed.total}',
              en: 'Found: ${feed.total}',
            ),
          ),
        ),
      ),
      SliverPadding(
        // Bottom: room to scroll the last card clear of the chat button.
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          feed.hasMore ? AppSpacing.md : kChatFabClearance,
        ),
        sliver: SliverLayoutBuilder(
          builder: (context, constraints) {
            return SliverGrid.builder(
              gridDelegate: _gridDelegate(context, constraints.crossAxisExtent),
              itemCount: items.length,
              itemBuilder: (context, i) {
                if (feed.hasMore && i >= items.length - 4) {
                  // Building a card near the end asks for the next page.
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      ref.read(catalogFeedProvider(query).notifier).loadMore();
                    }
                  });
                }
                final listing = items[i];
                final card = ServiceGridCard(
                  key: ValueKey('service-grid-${listing.id}'),
                  listing: listing,
                  locale: locale,
                  onTap: () {
                    ref.read(adTrackerProvider).opened(listing);
                    pushListingDetail(context, ref, listing);
                  },
                );
                return FadeSlideIn(
                  index: i,
                  child: listing.promoted && listing.promotionId != null
                      ? AdImpressionTracker(
                          promotionId: listing.promotionId!,
                          child: card,
                        )
                      : card,
                );
              },
            );
          },
        ),
      ),
      if (feed.hasMore)
        const SliverPadding(
          padding: EdgeInsets.only(bottom: kChatFabClearance),
          sliver: SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.sm),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final categories = ref.watch(categoriesProvider);
    final listingsKey = widget.initialCategorySlug;
    final query = CatalogQuery(categorySlug: listingsKey, search: _search);
    final feed = ref.watch(catalogFeedProvider(query));
    final category = categories.valueOrNull
        ?.where((c) => c.slug == listingsKey)
        .firstOrNull;

    return Scaffold(
      // This screen doubles as a bottom-nav tab root (no back button) *and*
      // a pushed screen (from Home's category tap or Categories' grid) — so
      // the button, unlike Service Detail's, still has to stay conditional
      // on `canPop`, same as the default `BackButton` would be.
      appBar: AppBar(
        title: Text(
          category?.name(locale) ??
              t(locale, ru: 'Услуги', kz: 'Қызметтер', en: 'Services'),
        ),
        leading: Navigator.canPop(context) ? const AppBackButton() : null,
        titleSpacing: Navigator.canPop(context) ? null : AppSpacing.md,
        // A slightly shorter bar keeps the title close to the city filter.
        toolbarHeight: 48,
      ),
      // One scroll view for filters and results: the category grid is
      // several rows tall, so pinning it above the list would leave too
      // little room for the results on small phones.
      body: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xxs,
              AppSpacing.md,
              0,
            ),
            sliver: SliverList.list(
              children: [
                // Same global city as Home — changing it here refetches this
                // list with the active category and search text kept.
                const ServicesCitySelector(),
                const SizedBox(height: AppSpacing.sm),
                _SearchField(
                  controller: _searchController,
                  locale: locale,
                  onChanged: _onSearchChanged,
                  onClear: _clearSearch,
                ),
                // While searching, the results come right under the field.
                if (listingsKey == null && _search.isEmpty)
                  ...categories.when(
                    loading: () => [
                      const SizedBox(height: AppSpacing.lg),
                      const _CategoryGridSkeleton(),
                    ],
                    error: (err, _) => const <Widget>[],
                    data: (list) => [
                      const SizedBox(height: AppSpacing.lg),
                      _SectionTitle(
                        t(
                          locale,
                          ru: 'Категории',
                          kz: 'Санаттар',
                          en: 'Categories',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      ServicesCategoryGrid(
                        categories: list,
                        locale: locale,
                        onSelect: _openCategory,
                      ),
                    ],
                  ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
          ..._resultSlivers(context, locale, query, feed),
        ],
      ),
    );
  }
}

/// The gap between the two columns of service cards.
const _gridColumnGap = AppSpacing.sm;

/// Two columns at every phone width; one fixed card height (from the
/// column width and font scale) keeps the rows even.
SliverGridDelegate _gridDelegate(BuildContext context, double width) {
  final cardWidth = (width - _gridColumnGap) / 2;
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 2,
    crossAxisSpacing: _gridColumnGap,
    mainAxisSpacing: AppSpacing.md,
    mainAxisExtent: ServiceGridCard.mainAxisExtent(
      cardWidth,
      MediaQuery.textScalerOf(context),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

/// A soft search field in the same card language as the city selector,
/// with a clear button once there's text.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.locale,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final AppLocale locale;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(kServicesRadius),
      borderSide: BorderSide(
        color: colors.border.withValues(alpha: colors.border.a * 0.6),
      ),
    );
    return SizedBox(
      height: 50,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: Theme.of(context).textTheme.bodyLarge,
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          // Lighter than the default input fill, so the search field never
          // competes with the city card or a selected category.
          fillColor: Color.lerp(colors.inputBackground, colors.surface, 0.5),
          hintText: t(
            locale,
            ru: 'Поиск услуг',
            kz: 'Қызметтерді іздеу',
            en: 'Search services',
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: colors.textSecondary,
            size: 20,
          ),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: t(
                      locale,
                      ru: 'Очистить',
                      kz: 'Тазарту',
                      en: 'Clear',
                    ),
                    icon: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: colors.textSecondary,
                    ),
                    onPressed: onClear,
                  ),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 0,
          ),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: BorderSide(color: colors.goldPrimary, width: 1.4),
          ),
        ),
      ),
    );
  }
}

/// Placeholder tiles while categories load — same 2-column rhythm as the
/// real grid so nothing jumps when it arrives.
class _CategoryGridSkeleton extends StatelessWidget {
  const _CategoryGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: 76,
        mainAxisSpacing: AppSpacing.xs,
        crossAxisSpacing: AppSpacing.xs,
      ),
      children: List.generate(
        6,
        (_) => const AppSkeleton(height: 76, borderRadius: kServicesRadius),
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults({
    required this.locale,
    required this.showReset,
    required this.onReset,
  });

  final AppLocale locale;
  final bool showReset;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppIconBadge(
              icon: Icons.search_off_rounded,
              size: 56,
              iconSize: 26,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              t(
                locale,
                ru: 'Услуги не найдены',
                kz: 'Қызметтер табылмады',
                en: 'No services found',
              ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (showReset) ...[
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton(
                onPressed: onReset,
                child: Text(
                  t(
                    locale,
                    ru: 'Сбросить фильтры',
                    kz: 'Сүзгілерді тазарту',
                    en: 'Clear filters',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
