import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../core/utils/listing_navigation.dart';
import '../../state/categories_provider.dart';
import '../../state/listings_provider.dart';
import '../../state/locale_provider.dart';
import '../../widgets/chat/chat_fab.dart';
import '../../widgets/app_back_button.dart';
import '../../widgets/app_error_view.dart';
import '../../widgets/app_icon_badge.dart';
import '../../widgets/app_skeleton.dart';
import '../../widgets/fade_slide_in.dart';
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
/// The list uses a single column of horizontal cards ([ServiceListTile])
/// rather than a 2-column grid: listing names/cities vary a lot in length,
/// and a full-width row gives text room to wrap/ellipsis cleanly instead of
/// fighting a narrow, fixed-height grid tile.
class ServicesScreen extends ConsumerStatefulWidget {
  const ServicesScreen({super.key, this.initialCategorySlug});

  /// Non-null when opened from a category card, matching the site's
  /// `/services?category=<slug>` deep link.
  final String? initialCategorySlug;

  @override
  ConsumerState<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends ConsumerState<ServicesScreen> {
  late String? _activeSlug = widget.initialCategorySlug;
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

  void _resetFilters() {
    setState(() {
      _activeSlug = null;
      _search = '';
      _searchController.clear();
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    setState(() => _search = '');
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final categories = ref.watch(categoriesProvider);
    final listingsKey = _activeSlug;
    final listings = ref.watch(listingsProvider(listingsKey));

    return Scaffold(
      // This screen doubles as a bottom-nav tab root (no back button) *and*
      // a pushed screen (from Home's category tap or Categories' grid) — so
      // the button, unlike Service Detail's, still has to stay conditional
      // on `canPop`, same as the default `BackButton` would be.
      appBar: AppBar(
        title: Text(t(locale, ru: 'Услуги', kz: 'Қызметтер', en: 'Services')),
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
                      activeSlug: _activeSlug,
                      locale: locale,
                      onSelect: (slug) => setState(() => _activeSlug = slug),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
          ...listings.when(
            loading: () => [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.xl,
                ),
                sliver: SliverList.separated(
                  itemCount: 5,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, i) => const AppSkeleton(
                    height: 128,
                    borderRadius: AppRadius.lg,
                  ),
                ),
              ),
            ],
            error: (err, _) => [
              SliverFillRemaining(
                hasScrollBody: false,
                child: AppErrorView(
                  message: apiErrorMessage(locale, err),
                  locale: locale,
                  onRetry: () => ref.invalidate(listingsProvider(listingsKey)),
                ),
              ),
            ],
            data: (all) {
              final filtered = _search.isEmpty
                  ? all
                  : all
                        .where(
                          (l) => l
                              .name(locale)
                              .toLowerCase()
                              .contains(_search.toLowerCase()),
                        )
                        .toList();
              final filtersActive = _activeSlug != null || _search.isNotEmpty;
              if (filtered.isEmpty) {
                return [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyResults(
                      locale: locale,
                      showReset: filtersActive,
                      onReset: _resetFilters,
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
                        ru: 'Найдено: ${filtered.length}',
                        kz: 'Табылды: ${filtered.length}',
                        en: 'Found: ${filtered.length}',
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  // Bottom: room to scroll the last card clear of the chat
                  // button.
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    0,
                    AppSpacing.md,
                    kChatFabClearance,
                  ),
                  sliver: SliverList.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, i) {
                      final listing = filtered[i];
                      return FadeSlideIn(
                        index: i,
                        child: ServiceListTile(
                          listing: listing,
                          locale: locale,
                          categoryLabel: listing.category?.name(locale),
                          onTap: () => pushListingDetail(context, ref, listing),
                        ),
                      );
                    },
                  ),
                ),
              ];
            },
          ),
        ],
      ),
    );
  }
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
