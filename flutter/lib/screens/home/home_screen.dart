import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../core/utils/format.dart';
import '../../state/categories_provider.dart';
import '../../state/listings_provider.dart';
import '../../state/locale_provider.dart';
import '../../state/statistics_provider.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_error_view.dart';
import '../../widgets/app_skeleton.dart';
import '../../widgets/category_card.dart';
import '../../widgets/fade_slide_in.dart';
import '../../widgets/section_header.dart';
import '../../widgets/service_card.dart';
import '../categories/categories_screen.dart';
import '../root_shell.dart';
import '../service_detail/service_detail_screen.dart';
import '../services/services_screen.dart';

/// The mobile counterpart of frontend/src/app/page.js — Hero, Statistics
/// (GET /api/site-statistics), Categories (GET /api/categories) and a
/// Featured-services strip built from GET /api/listings, all on one screen.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);

    return Scaffold(
      body: RefreshIndicator(
        color: AppColors.goldPrimary,
        backgroundColor: AppColors.surfaceElevated,
        onRefresh: () async {
          ref.invalidate(statisticsProvider);
          ref.invalidate(categoriesProvider);
          ref.invalidate(listingsProvider(null));
        },
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              floating: true,
              backgroundColor: AppColors.backgroundPrimary,
              titleSpacing: AppSpacing.lg,
              title: const _BrandMark(),
              actions: [
                _LocaleToggle(locale: locale),
                const SizedBox(width: AppSpacing.md),
              ],
            ),
            SliverToBoxAdapter(child: _Hero(locale: locale)),
            SliverToBoxAdapter(child: _CategoriesSection(locale: locale)),
            SliverToBoxAdapter(child: _FeaturedSection(locale: locale)),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
          ],
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: const TextSpan(
        style: TextStyle(fontFamily: 'PlayfairDisplay', fontWeight: FontWeight.w800, fontSize: 18),
        children: [
          TextSpan(text: 'MEREY', style: TextStyle(color: AppColors.textPrimary)),
          TextSpan(text: 'TOI', style: TextStyle(color: AppColors.goldPrimary)),
        ],
      ),
    );
  }
}

class _LocaleToggle extends ConsumerWidget {
  const _LocaleToggle({required this.locale});

  final AppLocale locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 44,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.chip),
          onTap: () => ref.read(localeProvider.notifier).state = locale == AppLocale.ru ? AppLocale.kz : AppLocale.ru,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Text(
                locale == AppLocale.ru ? 'ҚАЗ' : 'РУС',
                style: const TextStyle(color: AppColors.goldSoft, fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Hero extends ConsumerWidget {
  const _Hero({required this.locale});

  final AppLocale locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, AppSpacing.md),
      decoration: const BoxDecoration(
        gradient: RadialGradient(center: Alignment(0, -0.9), radius: 1.2, colors: [AppColors.heroGlow, AppColors.backgroundPrimary]),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.goldPrimary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Text(
              t(locale, ru: 'АГЕНТСТВО ТОРЖЕСТВ', kz: 'ТОЙ АГЕНТТІГІ'),
              style: const TextStyle(color: AppColors.goldPrimary, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.6),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            t(locale, ru: 'Той вашей мечты', kz: 'Армандаған тойыңыз'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 25),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            t(locale, ru: 'Традиции встречаются с современным стилем', kz: 'Дәстүр мен заманауи сән ұштасады'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          ElevatedButton.icon(
            onPressed: () => ref.read(selectedTabProvider.notifier).state = 1,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
            ),
            icon: const Icon(Icons.arrow_forward_rounded, size: 16),
            label: Text(t(locale, ru: 'Смотреть услуги', kz: 'Қызметтерді қарау')),
          ),
          const SizedBox(height: AppSpacing.sm),
          _StatisticsCard(locale: locale),
        ],
      ),
    );
  }
}

class _StatisticsCard extends ConsumerWidget {
  const _StatisticsCard({required this.locale});

  final AppLocale locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statisticsProvider);

    return stats.when(
      loading: () => const AppSkeleton(height: 88, borderRadius: AppRadius.lg),
      error: (err, _) => const SizedBox.shrink(), // stats are decorative — a failure here shouldn't block the rest of Home
      data: (s) {
        final tiles = [
          (formatStatValue(s.eventsCount), t(locale, ru: 'Тоев', kz: 'Той')),
          (formatStatValue(s.happyGuestsCount), t(locale, ru: 'Гостей', kz: 'Қонақ')),
          (formatStatValue(s.yearsExperience), t(locale, ru: 'Лет', kz: 'Жыл')),
          (formatStatValue(s.citiesCount), t(locale, ru: 'Городов', kz: 'Қала')),
        ];
        return AppCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const _StatDivider(),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          tiles[i].$1,
                          maxLines: 1,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.goldSoft, fontSize: 14),
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        tiles[i].$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 18, color: AppColors.divider);
  }
}

class _CategoriesSection extends ConsumerWidget {
  const _CategoriesSection({required this.locale});

  final AppLocale locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: SectionHeader(
                  eyebrow: t(locale, ru: 'Что мы предлагаем', kz: 'Не ұсынамыз'),
                  title: t(locale, ru: 'Услуги', kz: 'Қызметтер'),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CategoriesScreen())),
                child: Text(t(locale, ru: 'Все', kz: 'Барлығы')),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          categories.when(
            loading: () => const AppGridSkeleton(itemCount: 4, aspectRatio: 0.92),
            error: (err, _) => AppErrorView(
              message: apiErrorMessage(locale, err),
              locale: locale,
              onRetry: () => ref.invalidate(categoriesProvider),
            ),
            data: (list) {
              if (list.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Text(t(locale, ru: 'Категории скоро появятся', kz: 'Санаттар жақында қосылады'), style: Theme.of(context).textTheme.bodyMedium),
                );
              }
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: list.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: AppSpacing.md,
                  crossAxisSpacing: AppSpacing.md,
                  childAspectRatio: 0.92,
                ),
                itemBuilder: (context, i) {
                  final category = list[i];
                  return FadeSlideIn(
                    index: i,
                    child: CategoryCard(
                      category: category,
                      locale: locale,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => ServicesScreen(initialCategorySlug: category.slug)),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FeaturedSection extends ConsumerWidget {
  const _FeaturedSection({required this.locale});

  final AppLocale locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listings = ref.watch(listingsProvider(null));

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: SectionHeader(
              eyebrow: t(locale, ru: 'Рекомендуем', kz: 'Ұсынамыз'),
              title: t(locale, ru: 'Популярные услуги', kz: 'Танымал қызметтер'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          listings.when(
            loading: () => SizedBox(
              height: 284,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                itemCount: 3,
                separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
                itemBuilder: (context, i) => const SizedBox(width: 168, child: AppCardSkeleton(aspectRatio: 1.15)),
              ),
            ),
            error: (err, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: AppErrorView(message: apiErrorMessage(locale, err), locale: locale, onRetry: () => ref.invalidate(listingsProvider(null))),
            ),
            data: (list) {
              if (list.isEmpty) return const SizedBox.shrink();
              final featured = list.take(6).toList();
              return SizedBox(
                height: 284,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  itemCount: featured.length,
                  separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
                  itemBuilder: (context, i) {
                    final listing = featured[i];
                    return FadeSlideIn(
                      index: i,
                      child: SizedBox(
                        width: 168,
                        child: ServiceCard(
                          listing: listing,
                          locale: locale,
                          categoryLabel: listing.category?.name(locale),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => ServiceDetailScreen(listingId: listing.id)),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
