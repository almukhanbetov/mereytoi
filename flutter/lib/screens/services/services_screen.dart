import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../state/categories_provider.dart';
import '../../state/listings_provider.dart';
import '../../state/locale_provider.dart';
import '../../widgets/app_back_button.dart';
import '../../widgets/app_error_view.dart';
import '../../widgets/app_skeleton.dart';
import '../../widgets/category_filter_bar.dart';
import '../../widgets/fade_slide_in.dart';
import '../../widgets/service_card.dart';
import '../service_detail/service_detail_screen.dart';

/// The mobile counterpart of the site's /services catalog
/// (frontend/src/components/services/ServicesClient.jsx): a category-chip
/// filter row plus a list of listings, both backed by the *same*
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
        title: Text(t(locale, ru: 'Услуги', kz: 'Қызметтер')),
        leading: Navigator.canPop(context) ? const AppBackButton() : null,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xxs, AppSpacing.lg, AppSpacing.sm),
            child: SizedBox(
              height: 44,
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: Theme.of(context).textTheme.bodyLarge,
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: t(locale, ru: 'Поиск услуг', kz: 'Қызметтерді іздеу'),
                  prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary, size: 18),
                  contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 0),
                ),
              ),
            ),
          ),
          // CategoryFilterBar owns its own horizontal padding (its lane's
          // scroll padding needs to be asymmetric — a wider trailing edge
          // for the "Все категории" chip) so it isn't wrapped in one here.
          categories.when(
            loading: () => const SizedBox.shrink(),
            error: (err, _) => const SizedBox.shrink(),
            data: (list) => CategoryFilterBar(
              categories: list,
              activeSlug: _activeSlug,
              locale: locale,
              onSelect: (slug) => setState(() => _activeSlug = slug),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: listings.when(
              loading: () => ListView.separated(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
                itemCount: 5,
                separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                itemBuilder: (context, i) => const AppSkeleton(height: 128, borderRadius: AppRadius.lg),
              ),
              error: (err, _) => AppErrorView(
                message: apiErrorMessage(locale, err),
                locale: locale,
                onRetry: () => ref.invalidate(listingsProvider(listingsKey)),
              ),
              data: (all) {
                final filtered = _search.isEmpty
                    ? all
                    : all.where((l) => l.name(locale).toLowerCase().contains(_search.toLowerCase())).toList();
                final filtersActive = _activeSlug != null || _search.isNotEmpty;
                if (filtered.isEmpty) {
                  return _EmptyResults(locale: locale, showReset: filtersActive, onReset: _resetFilters);
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                  itemBuilder: (context, i) {
                    final listing = filtered[i];
                    return FadeSlideIn(
                      index: i,
                      child: ServiceListTile(
                        listing: listing,
                        locale: locale,
                        categoryLabel: listing.category?.name(locale),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => ServiceDetailScreen(listingId: listing.id)),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults({required this.locale, required this.showReset, required this.onReset});

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
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: const Icon(Icons.search_off_rounded, color: AppColors.textSecondary, size: 26),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(t(locale, ru: 'Услуги не найдены', kz: 'Қызметтер табылмады'), style: Theme.of(context).textTheme.titleMedium),
            if (showReset) ...[
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton(onPressed: onReset, child: Text(t(locale, ru: 'Сбросить фильтры', kz: 'Сүзгілерді тазарту'))),
            ],
          ],
        ),
      ),
    );
  }
}
