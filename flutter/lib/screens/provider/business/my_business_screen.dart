import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/api_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/error_messages.dart';
import '../../../models/provider_profile.dart';
import '../../../state/listings_provider.dart';
import '../../../state/locale_provider.dart';
import '../../../state/provider_business.dart';
import '../../../state/provider_provider.dart';
import '../../../widgets/app_error_view.dart';
import '../../../widgets/network_image_box.dart';
import '../../profile/provider/my_services_screen.dart';
import '../../profile/provider/widgets/provider_profile_form_sheet.dart';
import '../../provider_chat/provider_chat_list_screen.dart';
import '../onboarding/provider_onboarding_screen.dart';
import 'business_text.dart';
import 'provider_bookings_screen.dart';
import 'provider_statistics_screen.dart';

/// «Мой бизнес» — the provider's hub, opened from Home and Profile (no
/// extra bottom tab): profile header, then Мои услуги / Заявки / Сообщения
/// / Профиль / Статистика, each leading to the existing screen for it.
class MyBusinessScreen extends ConsumerStatefulWidget {
  const MyBusinessScreen({super.key});

  @override
  ConsumerState<MyBusinessScreen> createState() => _MyBusinessScreenState();
}

class _MyBusinessScreenState extends ConsumerState<MyBusinessScreen> {
  @override
  void initState() {
    super.initState();
    // Providers come here to see new requests — always start from fresh
    // counts rather than whatever was cached when the app opened.
    Future.microtask(() {
      if (!mounted) return;
      ref.invalidate(providerBookingsProvider);
      ref.invalidate(myListingsProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final provider = ref.watch(providerProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          t(locale, ru: 'Мой бизнес', kz: 'Менің бизнесім', en: 'My business'),
        ),
      ),
      body: provider.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => AppErrorView(
          message: apiErrorMessage(locale, err),
          locale: locale,
          onRetry: () => ref.invalidate(providerProfileProvider),
        ),
        data: (profile) => profile == null
            ? _NotAProvider(locale: locale)
            : _BusinessBody(locale: locale, profile: profile),
      ),
    );
  }
}

class _BusinessBody extends ConsumerWidget {
  const _BusinessBody({required this.locale, required this.profile});

  final AppLocale locale;
  final ProviderProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(myServicesCountProvider);
    final bookings = ref.watch(myBookingsCountProvider);

    void push(Widget screen) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

    return RefreshIndicator(
      color: context.mereytoiColors.goldPrimary,
      onRefresh: () async {
        ref.invalidate(providerProfileProvider);
        ref.invalidate(myListingsProvider);
        ref.invalidate(providerBookingsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        children: [
          _ProfileHeader(locale: locale, profile: profile),
          const SizedBox(height: AppSpacing.lg),
          _HubTile(
            key: const ValueKey('business-services'),
            icon: Icons.grid_view_rounded,
            title: t(
              locale,
              ru: 'Мои услуги',
              kz: 'Менің қызметтерім',
              en: 'My services',
            ),
            subtitle: services == null
                ? null
                : services == 0
                ? t(
                    locale,
                    ru: 'Добавьте первую услугу',
                    kz: 'Алғашқы қызметті қосыңыз',
                    en: 'Add your first service',
                  )
                : servicesCountLabel(locale, services),
            onTap: () => push(const MyServicesScreen()),
          ),
          _HubTile(
            key: const ValueKey('business-bookings'),
            icon: Icons.inbox_rounded,
            title: t(locale, ru: 'Заявки', kz: 'Өтінімдер', en: 'Requests'),
            subtitle: bookings == null
                ? null
                : bookings == 0
                ? t(
                    locale,
                    ru: 'Пока нет заявок',
                    kz: 'Әзірге өтінім жоқ',
                    en: 'No requests yet',
                  )
                : bookingsCountLabel(locale, bookings),
            onTap: () {
              // New requests may have arrived since this screen opened.
              ref.invalidate(providerBookingsProvider);
              push(const ProviderBookingsScreen());
            },
          ),
          _HubTile(
            key: const ValueKey('business-messages'),
            icon: Icons.chat_bubble_outline_rounded,
            title: t(
              locale,
              ru: 'Сообщения',
              kz: 'Хабарламалар',
              en: 'Messages',
            ),
            subtitle: t(
              locale,
              ru: 'Переписка с клиентами',
              kz: 'Клиенттермен хат алмасу',
              en: 'Conversations with clients',
            ),
            onTap: () => push(const ProviderChatListScreen()),
          ),
          _HubTile(
            key: const ValueKey('business-profile'),
            icon: Icons.person_outline_rounded,
            title: t(locale, ru: 'Профиль', kz: 'Профиль', en: 'Profile'),
            subtitle: t(
              locale,
              ru: 'Имя, описание, контакты',
              kz: 'Аты, сипаттама, байланыс',
              en: 'Name, description, contacts',
            ),
            onTap: () =>
                openProviderProfileFormSheet(context, existing: profile),
          ),
          _HubTile(
            key: const ValueKey('business-statistics'),
            icon: Icons.insights_rounded,
            title: t(
              locale,
              ru: 'Статистика',
              kz: 'Статистика',
              en: 'Statistics',
            ),
            subtitle: t(locale, ru: 'Скоро', kz: 'Жақында', en: 'Coming soon'),
            onTap: () => push(const ProviderStatisticsScreen()),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.locale, required this.profile});

  final AppLocale locale;
  final ProviderProfile profile;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    final textTheme = Theme.of(context).textTheme;
    final name = profile.displayName.trim();
    final meta = [
      if (profile.city.trim().isNotEmpty) profile.city.trim(),
      if (profile.experienceYears != null)
        experienceLabel(locale, profile.experienceYears!),
    ].join(' · ');

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F1A1611),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            ClipOval(
              child: SizedBox(
                width: 64,
                height: 64,
                child: profile.avatarUrl.isNotEmpty
                    ? NetworkImageBox(
                        url: ApiConfig.mediaUrl(profile.avatarUrl),
                        borderRadius: 0,
                        fallbackIcon: Icons.person_rounded,
                      )
                    : ColoredBox(
                        color: colors.goldPrimary.withValues(alpha: 0.14),
                        child: Center(
                          child: Text(
                            name.isEmpty
                                ? '?'
                                : name.characters.first.toUpperCase(),
                            style: textTheme.titleLarge?.copyWith(
                              color: colors.goldPrimary,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    key: const ValueKey('business-name'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      key: const ValueKey('business-meta'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: profile.status == 'active'
                          ? colors.success.withValues(alpha: 0.12)
                          : colors.warning.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                    ),
                    child: Text(
                      providerStatusLabel(locale, profile.status),
                      key: const ValueKey('business-status'),
                      style: textTheme.labelSmall?.copyWith(
                        color: profile.status == 'active'
                            ? colors.success
                            : colors.warning,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HubTile extends StatelessWidget {
  const _HubTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: colors.border),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 68),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: colors.goldPrimary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: colors.goldPrimary, size: 22),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (subtitle != null)
                            Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: colors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Reached only if the profile disappears while the screen is open (e.g. a
/// different account signed in) — offers the onboarding instead of an
/// empty hub.
class _NotAProvider extends StatelessWidget {
  const _NotAProvider({required this.locale});

  final AppLocale locale;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t(
                locale,
                ru: 'У вас пока нет профиля услугодателя',
                kz: 'Сізде әлі қызмет көрсетуші профилі жоқ',
                en: 'You don\'t have a provider profile yet',
              ),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => const ProviderOnboardingScreen(),
                  ),
                ),
                child: Text(
                  t(
                    locale,
                    ru: 'Стать услугодателем',
                    kz: 'Қызмет көрсетуші болу',
                    en: 'Become a provider',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
