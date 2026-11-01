import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../models/provider_profile.dart';
import '../../state/app_mode_provider.dart';
import '../../state/auth_provider.dart';
import '../../state/locale_provider.dart';
import '../../state/provider_provider.dart';
import '../auth/login_screen.dart';
import '../provider/business/my_business_screen.dart';
import '../provider/onboarding/provider_onboarding_screen.dart';
import '../root_shell.dart';

/// The business side for an account: «Мой бизнес» for a provider, the
/// provider onboarding (which then leads to «Мой бизнес») otherwise.
Route<void> businessRoute(ProviderProfile? provider) => MaterialPageRoute(
  builder: (_) => provider == null
      ? const ProviderOnboardingScreen(openBusinessWhenDone: true)
      : const MyBusinessScreen(),
);

/// The client app, as the navigator's only route.
Route<void> clientRootRoute() => PageRouteBuilder(
  transitionDuration: const Duration(milliseconds: 400),
  pageBuilder: (context, animation, _) =>
      FadeTransition(opacity: animation, child: const RootShell()),
);

/// «Выберите свой режим» — shown once, before the first launch picks a
/// mode: for an event (the client app as it is) or for business (the
/// provider onboarding, or «Мой бизнес» for a provider). One account
/// does both; the choice is only remembered as a UI preference.
class RoleChoiceScreen extends ConsumerStatefulWidget {
  const RoleChoiceScreen({super.key});

  @override
  ConsumerState<RoleChoiceScreen> createState() => _RoleChoiceScreenState();
}

class _RoleChoiceScreenState extends ConsumerState<RoleChoiceScreen> {
  AppMode? _selected;

  /// A guest chose business: carry on once they've signed in or signed up,
  /// without asking for the mode again.
  bool _continueAfterSignIn = false;
  bool _busy = false;

  static const _selectDelay = Duration(milliseconds: 220);

  Future<void> _choose(AppMode mode) async {
    if (_busy) return;
    setState(() => _selected = mode);
    // Let the selection show before the screen changes.
    await Future<void>.delayed(_selectDelay);
    if (!mounted) return;
    if (mode == AppMode.client) {
      ref.read(appModeProvider.notifier).set(AppMode.client);
      Navigator.of(context).pushAndRemoveUntil(clientRootRoute(), (_) => false);
      return;
    }
    if (ref.read(authProvider) is AuthAuthenticated) {
      await _openBusiness();
    } else {
      _continueAfterSignIn = true;
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  Future<void> _openBusiness() async {
    if (_busy) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    try {
      // Loaded while this screen is still alive; only then swap routes.
      final provider = await ref.read(providerProfileProvider.future);
      if (!mounted) return;
      ref.read(appModeProvider.notifier).set(AppMode.business);
      navigator
        ..pushAndRemoveUntil(clientRootRoute(), (_) => false)
        ..push(businessRoute(provider));
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      final locale = ref.read(localeProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              locale,
              ru: 'Не удалось загрузить. Попробуйте ещё раз',
              kz: 'Жүктеу мүмкін болмады. Қайталап көріңіз',
              en: 'Couldn’t load. Please try again',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final colors = context.mereytoiColors;
    final textTheme = Theme.of(context).textTheme;

    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next is! AuthAuthenticated || !_continueAfterSignIn) return;
      _continueAfterSignIn = false;
      // After the sign-in screen has closed itself and the previous
      // account's provider cache has been dropped (see app.dart).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openBusiness();
      });
    });

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          children: [
            Center(
              child: RichText(
                text: TextSpan(
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: colors.textPrimary,
                  ),
                  children: [
                    const TextSpan(text: 'MERE'),
                    TextSpan(
                      text: 'YTOI',
                      style: TextStyle(color: colors.goldPrimary),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Text(
              t(
                locale,
                ru: 'Один аккаунт — два режима',
                kz: 'Бір аккаунт — екі режим',
                en: 'One account, two modes',
              ),
              textAlign: TextAlign.center,
              style: textTheme.titleLarge?.copyWith(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              t(
                locale,
                ru:
                    'Выберите, что вы хотите делать сейчас. '
                    'Переключиться можно в любой момент.',
                kz:
                    'Қазір не істегіңіз келетінін таңдаңыз. '
                    'Кез келген уақытта ауыстыра аласыз.',
                en:
                    'Choose what you want to do now. '
                    'You can switch at any time.',
              ),
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            _EqualHeightPair(
              gap: AppSpacing.md,
              firstKey: const ValueKey('role-client'),
              secondKey: const ValueKey('role-business'),
              first: ModeChoiceCard(
                icon: Icons.celebration_rounded,
                eyebrow: t(
                  locale,
                  ru: 'Для мероприятия',
                  kz: 'Іс-шара үшін',
                  en: 'For an event',
                ),
                title: t(
                  locale,
                  ru: 'Ищу услуги',
                  kz: 'Қызмет іздеймін',
                  en: 'Looking for services',
                ),
                description: t(
                  locale,
                  ru: 'Рестораны, ведущие, фотографы, шоу-программы и другое',
                  kz:
                      'Мейрамханалар, жүргізушілер, фотографтар, '
                      'шоу-бағдарламалар және басқа қызметтер',
                  en: 'Restaurants, hosts, photographers, shows and more',
                ),
                cta: t(
                  locale,
                  ru: 'Продолжить',
                  kz: 'Жалғастыру',
                  en: 'Continue',
                ),
                selected: _selected == AppMode.client,
                onTap: () => _choose(AppMode.client),
              ),
              second: ModeChoiceCard(
                icon: Icons.business_center_rounded,
                eyebrow: t(
                  locale,
                  ru: 'Для бизнеса',
                  kz: 'Бизнес үшін',
                  en: 'For business',
                ),
                title: t(
                  locale,
                  ru: 'Предлагаю услуги',
                  kz: 'Қызмет ұсынамын',
                  en: 'Offering services',
                ),
                description: t(
                  locale,
                  ru: 'Размещаю услуги, получаю заявки и управляю бизнесом',
                  kz:
                      'Қызметтерді орналастырамын, өтінім аламын және '
                      'бизнесімді басқарамын',
                  en: 'I list services, get requests and run my business',
                ),
                goldAccent: true,
                cta: t(
                  locale,
                  ru: 'Продолжить',
                  kz: 'Жалғастыру',
                  en: 'Continue',
                ),
                selected: _selected == AppMode.business,
                busy: _busy,
                onTap: () => _choose(AppMode.business),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two cards stacked vertically at one height — the taller one's — so the
/// two modes look like equal options whatever the text length. Each slot
/// sizes itself to invisible, inert copies of both cards and lays its real
/// card over them.
class _EqualHeightPair extends StatelessWidget {
  const _EqualHeightPair({
    required this.first,
    required this.second,
    required this.gap,
    this.firstKey,
    this.secondKey,
  });

  final Widget first;
  final Widget second;
  final double gap;
  final Key? firstKey;
  final Key? secondKey;

  Widget _slot(Widget card, Key? key) {
    Widget ghost(Widget w) => ExcludeSemantics(
      child: IgnorePointer(child: Opacity(opacity: 0, child: w)),
    );
    return Stack(
      children: [
        ghost(first),
        ghost(second),
        Positioned.fill(
          child: KeyedSubtree(key: key, child: card),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _slot(first, firstKey),
        SizedBox(height: gap),
        _slot(second, secondKey),
      ],
    );
  }
}

/// A mode card: icon, eyebrow (the mode), title (the action), a short
/// description and an optional CTA line. «Для мероприятия» cards stay
/// neutral and warm; «Для бизнеса» cards ([goldAccent]) carry a stronger
/// gold accent, so the two read as different roles at a glance. Selected:
/// gold border, a light warm gold wash, a check mark and a slight
/// scale-up. Both roles' cards are the same size: the description always
/// reserves [descriptionLines] lines. Also used, compact, in Profile.
class ModeChoiceCard extends StatelessWidget {
  const ModeChoiceCard({
    super.key,
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.selected,
    required this.onTap,
    this.description,
    this.cta,
    this.goldAccent = false,
    this.busy = false,
    this.compact = false,
    this.descriptionLines = 2,
  });

  final IconData icon;
  final String eyebrow;
  final String title;
  final String? description;
  final String? cta;
  final bool selected;
  final bool goldAccent;
  final bool busy;
  final int descriptionLines;

  /// Profile's version: smaller padding and icon.
  final bool compact;
  final VoidCallback onTap;

  static const radius = 24.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    final textTheme = Theme.of(context).textTheme;
    final cardRadius = compact ? 22.0 : radius;
    final iconSize = compact ? 40.0 : 56.0;

    final Color background;
    if (selected) {
      background = Color.alphaBlend(
        colors.goldPrimary.withValues(alpha: 0.09),
        colors.surface,
      );
    } else if (goldAccent) {
      background = colors.surface;
    } else {
      // The event side: a barely warm off-white.
      background = Color.alphaBlend(
        colors.goldPrimary.withValues(alpha: 0.035),
        colors.surface,
      );
    }

    final Color badge;
    final Color badgeIcon;
    if (selected) {
      badge = colors.goldPrimary;
      badgeIcon = colors.onGold;
    } else if (goldAccent) {
      badge = colors.goldPrimary.withValues(alpha: 0.18);
      badgeIcon = colors.goldPrimary;
    } else {
      badge = colors.textPrimary.withValues(alpha: 0.06);
      badgeIcon = colors.textSecondary;
    }

    final descriptionStyle = textTheme.bodyMedium?.copyWith(
      color: colors.textSecondary,
      height: 1.35,
    );
    final descriptionMinHeight =
        MediaQuery.textScalerOf(
          context,
        ).scale(descriptionStyle?.fontSize ?? 14) *
        1.35 *
        descriptionLines;

    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedScale(
        scale: selected ? (compact ? 1.0 : 1.02) : 1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(cardRadius),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0F1A1611),
                blurRadius: 16,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Material(
            color: background,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(cardRadius),
              side: BorderSide(
                color: selected
                    ? colors.goldPrimary
                    // No heavy frame: just enough to hold the edge in dark mode.
                    : colors.border.withValues(alpha: colors.border.a * 0.5),
                width: selected ? 1.75 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: busy ? null : onTap,
              child: Padding(
                padding: EdgeInsets.all(
                  compact ? AppSpacing.md : AppSpacing.lg,
                ),
                // When stretched to a taller sibling's height, the CTA line
                // stays at the bottom.
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: iconSize,
                              height: iconSize,
                              decoration: BoxDecoration(
                                color: badge,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                icon,
                                size: iconSize / 2,
                                color: badgeIcon,
                              ),
                            ),
                            const Spacer(),
                            AnimatedOpacity(
                              opacity: selected ? 1 : 0,
                              duration: const Duration(milliseconds: 180),
                              child: Icon(
                                Icons.check_circle_rounded,
                                key: const ValueKey('mode-selected-check'),
                                size: compact ? 20 : 24,
                                color: colors.goldPrimary,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(
                          height: compact ? AppSpacing.sm : AppSpacing.md,
                        ),
                        Text(
                          eyebrow,
                          style: textTheme.labelLarge?.copyWith(
                            color: goldAccent || selected
                                ? colors.goldSoft
                                : colors.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          title,
                          style: textTheme.titleLarge?.copyWith(
                            fontSize: compact ? 16 : 22,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                        if (description != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: descriptionMinHeight,
                            ),
                            child: Text(description!, style: descriptionStyle),
                          ),
                        ],
                      ],
                    ),
                    if (cta != null)
                      Padding(
                        padding: EdgeInsets.only(
                          top: compact ? AppSpacing.sm : AppSpacing.md,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                cta!,
                                style:
                                    (compact
                                            ? textTheme.labelLarge
                                            : textTheme.titleMedium)
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: colors.goldSoft,
                                        ),
                              ),
                            ),
                            if (busy)
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            else
                              Icon(
                                Icons.arrow_forward_rounded,
                                size: compact ? 18 : 24,
                                color: colors.goldSoft,
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
      ),
    );
  }
}
