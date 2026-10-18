import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/provider/business/business_text.dart';
import '../../screens/provider/business/my_business_screen.dart';
import '../../screens/provider/onboarding/provider_onboarding_screen.dart';
import '../../state/auth_provider.dart';
import '../../state/locale_provider.dart';
import '../../state/provider_business.dart';
import '../../state/provider_provider.dart';

/// Home's entry to the provider marketplace. For guests and users without
/// a provider profile it's the «Зарабатывайте вместе с MEREYTOI» promo
/// (→ onboarding, or sign-in first for a guest); for a provider it becomes
/// «Мой бизнес» (→ [MyBusinessScreen]) with real service/request counts
/// when they're loaded. Provider status comes only from the provider API
/// ([providerProfileProvider]), and the card stays hidden until that
/// answer is in, so it never flashes the wrong action.
class ProviderBusinessCard extends ConsumerWidget {
  const ProviderBusinessCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final auth = ref.watch(authProvider);

    if (auth is! AuthAuthenticated) {
      // Guests: no request, just the promo; the CTA signs in first.
      if (auth is! AuthUnauthenticated) return const SizedBox.shrink();
      return _PromoCard(
        locale: locale,
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const LoginScreen())),
      );
    }

    final provider = ref.watch(providerProfileProvider);
    return provider.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (profile) {
        if (profile == null) {
          return _PromoCard(
            locale: locale,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ProviderOnboardingScreen(),
              ),
            ),
          );
        }
        final services = ref.watch(myServicesCountProvider);
        final bookings = ref.watch(myBookingsCountProvider);
        return _BusinessCard(
          locale: locale,
          summary: [
            if (services != null) servicesCountLabel(locale, services),
            if (bookings != null) bookingsCountLabel(locale, bookings),
          ].join(' · '),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const MyBusinessScreen())),
        );
      },
    );
  }
}

class _PromoCard extends StatelessWidget {
  const _PromoCard({required this.locale, required this.onTap});

  final AppLocale locale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      key: const ValueKey('provider-promo-card'),
      icon: Icons.storefront_rounded,
      title: t(
        locale,
        ru: 'Зарабатывайте вместе с MEREYTOI',
        kz: 'MEREYTOI-мен бірге табыс табыңыз',
        en: 'Earn with MEREYTOI',
      ),
      subtitle: t(
        locale,
        ru: 'Размещайте свои услуги и находите новых клиентов',
        kz: 'Қызметтеріңізді орналастырып, жаңа клиенттер табыңыз',
        en: 'List your services and find new clients',
      ),
      cta: t(
        locale,
        ru: 'Стать услугодателем',
        kz: 'Қызмет көрсетуші болу',
        en: 'Become a provider',
      ),
      onTap: onTap,
    );
  }
}

class _BusinessCard extends StatelessWidget {
  const _BusinessCard({
    required this.locale,
    required this.summary,
    required this.onTap,
  });

  final AppLocale locale;
  final String summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      key: const ValueKey('provider-business-card'),
      icon: Icons.business_center_rounded,
      title: t(
        locale,
        ru: 'Мой бизнес',
        kz: 'Менің бизнесім',
        en: 'My business',
      ),
      subtitle: t(
        locale,
        ru: 'Управляйте услугами и заявками',
        kz: 'Қызметтер мен өтінімдерді басқарыңыз',
        en: 'Manage your services and requests',
      ),
      summary: summary.isEmpty ? null : summary,
      cta: t(locale, ru: 'Открыть', kz: 'Ашу', en: 'Open'),
      onTap: onTap,
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.cta,
    required this.onTap,
    this.summary,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? summary;
  final String cta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: DecoratedBox(
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          subtitle,
                          style: textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                        if (summary != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            summary!,
                            key: const ValueKey('provider-business-summary'),
                            style: textTheme.labelLarge?.copyWith(
                              color: colors.goldMuted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: colors.goldPrimary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: colors.goldPrimary, size: 26),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  key: const ValueKey('provider-card-cta'),
                  onPressed: onTap,
                  child: Text(
                    cta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
