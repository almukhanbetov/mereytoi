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
/// a provider profile it's the «Оказываете услуги?» promo
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
      title: t(
        locale,
        ru: 'Оказываете услуги?',
        kz: 'Қызмет көрсетесіз бе?',
        en: 'Do you provide services?',
      ),
      subtitle: t(
        locale,
        ru: 'Размещайте услуги на MEREYTOI и получайте заявки от клиентов',
        kz: 'Қызметтеріңізді MEREYTOI-де орналастырып, клиенттерден өтінім алыңыз',
        en: 'List your services on MEREYTOI and get requests from clients',
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
      title: t(
        locale,
        ru: 'Мой бизнес',
        kz: 'Менің бизнесім',
        en: 'My business',
      ),
      subtitle: t(
        locale,
        ru: 'Управляйте услугами, заявками и сообщениями',
        kz: 'Қызметтерді, өтінімдер мен хабарламаларды басқарыңыз',
        en: 'Manage your services, requests and messages',
      ),
      summary: summary.isEmpty ? null : summary,
      cta: t(locale, ru: 'Открыть', kz: 'Ашу', en: 'Open'),
      onTap: onTap,
    );
  }
}

/// A low, full-width secondary card — the app's second scenario, seen
/// early on Home but never competing with the hero: briefcase badge on the
/// left, title and a two-line description, then a bottom line with the
/// provider's counts (if any) and the CTA on the right. Warm light
/// background, a thin gold edge, a very soft shadow.
class _CardShell extends StatelessWidget {
  const _CardShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.cta,
    required this.onTap,
    this.summary,
  });

  final String title;
  final String subtitle;
  final String? summary;
  final String cta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    final textTheme = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(AppRadius.lg);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D1A1611),
              blurRadius: 12,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          color: Color.alphaBlend(
            colors.goldPrimary.withValues(alpha: 0.06),
            colors.surface,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: colors.goldPrimary.withValues(alpha: 0.35)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('provider-card-cta'),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.goldPrimary.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.business_center_rounded,
                      color: colors.goldPrimary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        // The provider's counts on the left (when known),
                        // the CTA on the right.
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (summary != null) ...[
                              // Counts are never cut off — on a narrow card
                              // they shrink a little instead.
                              Expanded(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    summary!,
                                    key: const ValueKey(
                                      'provider-business-summary',
                                    ),
                                    maxLines: 1,
                                    style: textTheme.labelLarge?.copyWith(
                                      color: colors.textPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                            ],
                            Flexible(
                              flex: summary == null ? 1 : 0,
                              child: Text(
                                cta,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.labelLarge?.copyWith(
                                  color: colors.goldSoft,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xxs),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 18,
                              color: colors.goldSoft,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
