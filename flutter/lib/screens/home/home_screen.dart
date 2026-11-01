import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../core/utils/format.dart';
import '../../core/utils/listing_navigation.dart';
import '../../state/auth_provider.dart';
import '../../state/categories_provider.dart';
import '../../state/city_provider.dart';
import '../../state/listings_provider.dart';
import '../../state/locale_provider.dart';
import '../../state/notification_providers.dart';
import '../../state/provider_provider.dart';
import '../../state/statistics_provider.dart';
import '../../state/theme_provider.dart';
import '../../widgets/chat/chat_fab.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_error_view.dart';
import '../../widgets/app_skeleton.dart';
import '../../widgets/category_card.dart';
import '../../widgets/city_selector.dart';
import '../../widgets/fade_slide_in.dart';
import '../../widgets/locale_sheet.dart';
import '../../widgets/provider/provider_business_card.dart';
import '../../widgets/section_header.dart';
import '../../widgets/service_card.dart';
import '../../widgets/theme_mode_sheet.dart';
import '../auth/login_screen.dart';
import '../notifications/notifications_screen.dart';
import '../profile/profile_screen.dart';
import '../root_shell.dart';
import '../services/services_screen.dart';

/// The app's showcase — Hero, Statistics (GET /api/site-statistics), city,
/// a few key categories (GET /api/categories), a few popular services
/// (GET /api/listings) and the provider entry. Every way into the full
/// list opens the services catalog ([ServicesScreen]).
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
          // A provider's «Мой бизнес» counts.
          ref.invalidate(providerBookingsProvider);
          ref.invalidate(myListingsProvider);
          // The city list is cached for the session; pull-to-refresh only
          // retries it when it actually failed.
          if (ref.read(citiesProvider).hasError) {
            ref.invalidate(citiesProvider);
          }
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
            // A short showcase, not a second catalog: hero, city, a few key
            // categories, a few popular offers, then the provider entry.
            // Finding a specific service is the «Услуги» tab's job.
            SliverToBoxAdapter(child: _Hero(locale: locale)),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.xs,
                  AppSpacing.lg,
                  0,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: CitySelectorButton(),
                ),
              ),
            ),
            SliverToBoxAdapter(child: _CategoriesSection(locale: locale)),
            SliverToBoxAdapter(child: _PopularSection(locale: locale)),
            // Provider marketplace entry — secondary, after the client
            // showcase: «Стать услугодателем» promo, or «Мой бизнес».
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: AppSpacing.md),
                child: ProviderBusinessCard(),
              ),
            ),
            // Room for the last section to scroll clear of the chat button.
            const SliverToBoxAdapter(
              child: SizedBox(height: kChatFabClearance),
            ),
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
          SectionHeader(
            eyebrow: t(
              locale,
              ru: 'Что мы предлагаем',
              kz: 'Не ұсынамыз',
              en: 'What we offer',
            ),
            title: t(locale, ru: 'Услуги', kz: 'Қызметтер', en: 'Services'),
          ),
          const SizedBox(height: AppSpacing.sm),
          categories.when(
            loading: () => const AppGridSkeleton(
              itemCount: _homeCategoryLimit,
              aspectRatio: 0.92,
            ),
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
              // Only the first few, in the catalog's own order — the rest
              // are one tap away in «Все услуги».
              final shown = list.take(_homeCategoryLimit).toList();
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: shown.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: AppSpacing.md,
                  crossAxisSpacing: AppSpacing.md,
                  childAspectRatio: 0.92,
                ),
                itemBuilder: (context, i) {
                  final category = shown[i];
                  return FadeSlideIn(
                    index: i,
                    child: CategoryCard(
                      category: category,
                      locale: locale,
                      onTap: () =>
                          _openCatalog(context, categorySlug: category.slug),
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const ValueKey('home-all-services'),
              onPressed: () => _openCatalog(context),
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: Text(
                t(
                  locale,
                  ru: 'Все услуги',
                  kz: 'Барлық қызметтер',
                  en: 'All services',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// How many categories and popular services Home shows — a glimpse, not
/// the catalog.
const _homeCategoryLimit = 4;
const _homePopularLimit = 4;

/// Opens the services catalog — filtered to [categorySlug], or showing
/// everything. Pushed, so Back returns to Home where it was.
void _openCatalog(BuildContext context, {String? categorySlug}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ServicesScreen(initialCategorySlug: categorySlug),
    ),
  );
}

/// «Популярное»: a 2×2 block of the catalog's own cards, with «Все →» to
/// the full catalog. Hidden when there's nothing to show.
class _PopularSection extends ConsumerWidget {
  const _PopularSection({required this.locale});

  final AppLocale locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listings = ref.watch(listingsProvider(null));
    if (listings case AsyncData(:final value) when value.isEmpty) {
      return const SizedBox.shrink();
    }

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
            children: [
              Expanded(
                child: SectionHeader(
                  eyebrow: t(
                    locale,
                    ru: 'Рекомендуем',
                    kz: 'Ұсынамыз',
                    en: 'Recommended',
                  ),
                  title: t(
                    locale,
                    ru: 'Популярное',
                    kz: 'Танымал',
                    en: 'Popular',
                  ),
                ),
              ),
              TextButton(
                key: const ValueKey('home-popular-all'),
                onPressed: () => _openCatalog(context),
                child: Text(t(locale, ru: 'Все', kz: 'Барлығы', en: 'All')),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          LayoutBuilder(
            builder: (context, constraints) {
              Widget grid(int count, Widget Function(int) item) =>
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    itemCount: count,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: AppSpacing.sm,
                      mainAxisSpacing: AppSpacing.md,
                      mainAxisExtent: ServiceGridCard.mainAxisExtent(
                        (constraints.maxWidth - AppSpacing.sm) / 2,
                        MediaQuery.textScalerOf(context),
                      ),
                    ),
                    itemBuilder: (context, i) => item(i),
                  );
              return listings.when(
                loading: () => grid(
                  _homePopularLimit,
                  (_) => const AppSkeleton(borderRadius: 16),
                ),
                error: (err, _) => AppErrorView(
                  message: apiErrorMessage(locale, err),
                  locale: locale,
                  onRetry: () => ref.invalidate(listingsProvider(null)),
                ),
                data: (list) {
                  final shown = list.take(_homePopularLimit).toList();
                  return grid(
                    shown.length,
                    (i) => FadeSlideIn(
                      index: i,
                      child: ServiceGridCard(
                        key: ValueKey('home-popular-${shown[i].id}'),
                        listing: shown[i],
                        locale: locale,
                        onTap: () => pushListingDetail(context, ref, shown[i]),
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
