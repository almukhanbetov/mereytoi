import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../core/utils/format.dart';
import '../../core/utils/listing_navigation.dart';
import '../../state/auth_provider.dart';
import '../../state/categories_provider.dart';
import '../../state/listings_provider.dart';
import '../../state/locale_provider.dart';
import '../../state/notification_providers.dart';
import '../../state/statistics_provider.dart';
import '../../state/theme_provider.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_error_view.dart';
import '../../widgets/app_skeleton.dart';
import '../../widgets/category_card.dart';
import '../../widgets/fade_slide_in.dart';
import '../../widgets/locale_sheet.dart';
import '../../widgets/section_header.dart';
import '../../widgets/service_card.dart';
import '../../widgets/theme_mode_sheet.dart';
import '../auth/login_screen.dart';
import '../categories/categories_screen.dart';
import '../notifications/notifications_screen.dart';
import '../profile/profile_screen.dart';
import '../root_shell.dart';
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
        color: context.mereytoiColors.goldPrimary,
        backgroundColor: context.mereytoiColors.surfaceElevated,
        onRefresh: () async {
          ref.invalidate(statisticsProvider);
          ref.invalidate(categoriesProvider);
          ref.invalidate(listingsProvider(null));
        },
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              floating: true,
              backgroundColor: context.mereytoiColors.backgroundPrimary,
              titleSpacing: AppSpacing.lg,
              title: const _BrandMark(),
              actions: [
                const _NotificationsButton(),
                const SizedBox(width: AppSpacing.xs),
                const _AccountButton(),
                const SizedBox(width: AppSpacing.xs),
                const _ThemeToggleButton(),
                const SizedBox(width: AppSpacing.xs),
                _LocaleToggle(locale: locale),
                const SizedBox(width: AppSpacing.md),
              ],
            ),
            SliverToBoxAdapter(child: _Hero(locale: locale)),
            SliverToBoxAdapter(child: _CategoriesSection(locale: locale)),
            SliverToBoxAdapter(
              child: _ListingCarouselSection(
                locale: locale,
                categorySlug: null,
                eyebrow: t(
                  locale,
                  ru: 'Рекомендуем',
                  kz: 'Ұсынамыз',
                  en: 'Recommended',
                ),
                title: t(
                  locale,
                  ru: 'Популярные услуги',
                  kz: 'Танымал қызметтер',
                  en: 'Popular services',
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _ListingCarouselSection(
                locale: locale,
                categorySlug: 'venues',
                eyebrow: t(
                  locale,
                  ru: 'Для торжества',
                  kz: 'Той үшін',
                  en: 'For your celebration',
                ),
                title: t(
                  locale,
                  ru: 'Рестораны',
                  kz: 'Мейрамханалар',
                  en: 'Restaurants',
                ),
              ),
            ),
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
      text: TextSpan(
        style: TextStyle(
          fontFamily: 'PlayfairDisplay',
          fontWeight: FontWeight.w800,
          fontSize: 18,
        ),
        children: [
          TextSpan(
            text: 'MEREY',
            style: TextStyle(color: context.mereytoiColors.textPrimary),
          ),
          TextSpan(
            text: 'TOI',
            style: TextStyle(color: context.mereytoiColors.goldPrimary),
          ),
        ],
      ),
    );
  }
}

/// The one entry point into auth/account. Guest → pushes [LoginScreen];
/// authenticated → pushes the full [ProfileScreen] (Stage 5) — logout
/// itself now lives there, not in a dialog off this icon.
class _AccountButton extends ConsumerWidget {
  const _AccountButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final authenticated = authState is AuthAuthenticated;

    return SizedBox(
      width: 44,
      height: 44,
      child: Material(
        color: context.mereytoiColors.surface,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    authenticated ? const ProfileScreen() : const LoginScreen(),
              ),
            );
          },
          child: Icon(
            authenticated ? Icons.person_rounded : Icons.person_outline_rounded,
            size: 19,
            color: authenticated
                ? context.mereytoiColors.goldPrimary
                : context.mereytoiColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Notifications entry point (brief section 2) — a bell + real unread
/// badge (`GET /api/notifications/unread-count`), not a 5th bottom-nav tab
/// (brief section 8 explicitly allows relocating this rather than
/// overloading `AppBottomNav`, which already carries
/// Главная/Услуги/Мой той/Корзина). Hidden entirely for a guest — same
/// "never call an endpoint that's a guaranteed 401" rule the rest of this
/// stage follows; `NotificationsScreen` itself still shows its own login
/// prompt for anyone who reaches it some other way.
class _NotificationsButton extends ConsumerWidget {
  const _NotificationsButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authenticated = ref.watch(authProvider) is AuthAuthenticated;
    final unread = authenticated
        ? ref.watch(unreadNotificationCountProvider).valueOrNull ?? 0
        : 0;

    return SizedBox(
      width: 44,
      height: 44,
      child: Material(
        color: context.mereytoiColors.surface,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const NotificationsScreen()),
          ),
          child: Badge(
            label: Text('$unread'),
            isLabelVisible: unread > 0,
            backgroundColor: context.mereytoiColors.error,
            textStyle: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
            child: Icon(
              Icons.notifications_outlined,
              size: 19,
              color: context.mereytoiColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Этап 10Б-А2 — the theme picker, reachable without logging in (the bug
/// report: it used to live only inside `ProfileScreen`, which a guest
/// never reaches — they get `LoginScreen` instead). Styled exactly like
/// `_AccountButton`/`_NotificationsButton` (44×44 circle on
/// `colors.surface`) rather than `_LocaleToggle`'s pill, since this shows
/// one glyph, not two-letter text; opens the exact same [ThemeModeSheet]
/// `ProfileScreen`'s own "Оформление" row does — one sheet, one
/// [themeModeProvider], never a second theme-picker UI to keep in sync.
class _ThemeToggleButton extends ConsumerWidget {
  const _ThemeToggleButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return SizedBox(
      width: 44,
      height: 44,
      child: Material(
        color: context.mereytoiColors.surface,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => const ThemeModeSheet(),
          ),
          child: Icon(
            themeModeIcon(mode),
            size: 19,
            color: context.mereytoiColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Этап 10Б-А3 fix: this used to show the current language as short text
/// ("РУС"/"ҚАЗ"/"ENG") — on the real device that reportedly rendered as
/// garbled/CJK-looking glyphs (Kazakh's extended Cyrillic, e.g. "Қ", can
/// trigger a font-fallback substitution on some Android builds that
/// doesn't happen for a fixed icon glyph) and, per the same report, didn't
/// visually update after switching. A constant `Icons.language_rounded`
/// glyph sidesteps both: nothing here depends on font-fallback behavior
/// for any script, and there's no per-language label to go stale — the
/// *icon* deliberately never changes (only [LocaleSheet]'s own checkmark
/// does); a screen reader still hears the current language via this
/// button's own [Semantics.label], which does update.
class _LocaleToggle extends ConsumerWidget {
  const _LocaleToggle({required this.locale});

  final AppLocale locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Semantics(
        button: true,
        label: t(
          locale,
          ru: 'Язык интерфейса: ${localeNativeName(locale)}',
          kz: 'Интерфейс тілі: ${localeNativeName(locale)}',
          en: 'Interface language: ${localeNativeName(locale)}',
        ),
        child: Material(
          color: context.mereytoiColors.surface,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const LocaleSheet(),
            ),
            child: Icon(
              Icons.language_rounded,
              size: 19,
              color: context.mereytoiColors.textSecondary,
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
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.9),
          radius: 1.2,
          colors: [
            context.mereytoiColors.heroGlow,
            context.mereytoiColors.backgroundPrimary,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 5,
            ),
            decoration: BoxDecoration(
              color: context.mereytoiColors.goldPrimary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Text(
              t(
                locale,
                ru: 'АГЕНТСТВО ТОРЖЕСТВ',
                kz: 'ТОЙ АГЕНТТІГІ',
                en: 'EVENT AGENCY',
              ),
              style: TextStyle(
                color: context.mereytoiColors.goldPrimary,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            t(
              locale,
              ru: 'Той вашей мечты',
              kz: 'Армандаған тойыңыз',
              en: 'The event of your dreams',
            ),
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.displayLarge?.copyWith(fontSize: 25),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            t(
              locale,
              ru: 'Традиции встречаются с современным стилем',
              kz: 'Дәстүр мен заманауи сән ұштасады',
              en: 'Where tradition meets modern style',
            ),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          ElevatedButton.icon(
            onPressed: () => ref.read(selectedTabProvider.notifier).state = 1,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xs,
              ),
            ),
            icon: const Icon(Icons.arrow_forward_rounded, size: 16),
            label: Text(
              t(
                locale,
                ru: 'Смотреть услуги',
                kz: 'Қызметтерді қарау',
                en: 'View services',
              ),
            ),
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
      error: (err, _) =>
          const SizedBox.shrink(), // stats are decorative — a failure here shouldn't block the rest of Home
      data: (s) {
        final tiles = [
          (
            formatStatValue(s.eventsCount),
            t(locale, ru: 'Тоев', kz: 'Той', en: 'Events'),
          ),
          (
            formatStatValue(s.happyGuestsCount),
            t(locale, ru: 'Гостей', kz: 'Қонақ', en: 'Guests'),
          ),
          (
            formatStatValue(s.yearsExperience),
            t(locale, ru: 'Лет', kz: 'Жыл', en: 'Years'),
          ),
          (
            formatStatValue(s.citiesCount),
            t(locale, ru: 'Городов', kz: 'Қала', en: 'Cities'),
          ),
        ];
        return AppCard(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.sm,
            horizontal: AppSpacing.xs,
          ),
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
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: context.mereytoiColors.goldSoft,
                                fontSize: 14,
                              ),
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
    return Container(
      width: 1,
      height: 18,
      color: context.mereytoiColors.divider,
    );
  }
}

class _CategoriesSection extends ConsumerWidget {
  const _CategoriesSection({required this.locale});

  final AppLocale locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: SectionHeader(
                  eyebrow: t(
                    locale,
                    ru: 'Что мы предлагаем',
                    kz: 'Не ұсынамыз',
                    en: 'What we offer',
                  ),
                  title: t(
                    locale,
                    ru: 'Услуги',
                    kz: 'Қызметтер',
                    en: 'Services',
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CategoriesScreen()),
                ),
                child: Text(t(locale, ru: 'Все', kz: 'Барлығы', en: 'All')),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          categories.when(
            loading: () =>
                const AppGridSkeleton(itemCount: 4, aspectRatio: 0.92),
            error: (err, _) => AppErrorView(
              message: apiErrorMessage(locale, err),
              locale: locale,
              onRetry: () => ref.invalidate(categoriesProvider),
            ),
            data: (list) {
              if (list.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Text(
                    t(
                      locale,
                      ru: 'Категории скоро появятся',
                      kz: 'Санаттар жақында қосылады',
                      en: 'Categories are coming soon',
                    ),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
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
                        MaterialPageRoute(
                          builder: (_) => ServicesScreen(
                            initialCategorySlug: category.slug,
                          ),
                        ),
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

/// A horizontally-scrolling listing rail with its own section header —
/// shared by "Популярные услуги" (`categorySlug: null`) and "Рестораны"
/// (`categorySlug: 'venues'`, the same real category slug
/// `RestaurantDetailScreen` already keys off of) so the loading/error/
/// empty handling for a card carousel is written once, not duplicated per
/// rail (Stage 8 — "унифицировать", "не плодить inline styles").
class _ListingCarouselSection extends ConsumerWidget {
  const _ListingCarouselSection({
    required this.locale,
    required this.categorySlug,
    required this.eyebrow,
    required this.title,
  });

  final AppLocale locale;
  final String? categorySlug;
  final String eyebrow;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listings = ref.watch(listingsProvider(categorySlug));

    // A genuinely empty rail (no venues yet, say) hides *itself* — header
    // included — rather than leaving a title sitting over blank space.
    // Loading/error still show the header, exactly as before: that's
    // useful feedback, unlike an empty result which has nothing to say.
    if (listings case AsyncData(:final value) when value.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: SectionHeader(eyebrow: eyebrow, title: title),
          ),
          const SizedBox(height: AppSpacing.sm),
          listings.when(
            loading: () => SizedBox(
              height: 284,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                itemCount: 3,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: AppSpacing.md),
                itemBuilder: (context, i) =>
                    const SizedBox(width: 168, child: AppCardSkeleton()),
              ),
            ),
            error: (err, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: AppErrorView(
                message: apiErrorMessage(locale, err),
                locale: locale,
                onRetry: () => ref.invalidate(listingsProvider(categorySlug)),
              ),
            ),
            data: (list) {
              // The empty case is already handled above (hides the whole
              // section, header included) before this `when` is even
              // reached — this branch only ever runs with a real list.
              final featured = list.take(6).toList();
              return SizedBox(
                height: 284,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  itemCount: featured.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: AppSpacing.md),
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
                          onTap: () => pushListingDetail(context, ref, listing),
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
