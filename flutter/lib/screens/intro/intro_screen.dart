import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/intro_storage.dart';
import '../../core/theme/app_theme.dart';
import '../../state/locale_provider.dart';
import '../../widgets/locale_sheet.dart';
import '../role_choice/role_choice_screen.dart';

/// The first-launch intro: three short pages — what MEREYTOI is, one
/// account with two modes, how it helps plan an event — then
/// «Начать» leads to the mode choice ([RoleChoiceScreen]). Shown once;
/// [IntroStorage] remembers it.
class IntroScreen extends ConsumerStatefulWidget {
  const IntroScreen({super.key});

  @override
  ConsumerState<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends ConsumerState<IntroScreen> {
  static const _pageCount = 3;
  final _controller = PageController();
  int _page = 0;
  bool _finishing = false;

  /// True while a page turn animates. The page index switches halfway
  /// through it, so without this a quick double tap on «Далее» would turn
  /// the second page and immediately act as «Начать», skipping the third.
  bool _turning = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_turning) return;
    if (_page < _pageCount - 1) {
      _turning = true;
      try {
        await _controller.nextPage(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      } finally {
        _turning = false;
      }
      return;
    }
    if (_finishing) return;
    _finishing = true;
    await IntroStorage.instance.markSeen();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (context, animation, _) =>
            FadeTransition(opacity: animation, child: const RoleChoiceScreen()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final colors = context.mereytoiColors;
    final last = _page == _pageCount - 1;

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xs,
                AppSpacing.md,
                0,
              ),
              child: Row(
                children: [
                  const Spacer(),
                  _LanguageButton(locale: locale),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                key: const ValueKey('intro-pages'),
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _WelcomePage(locale: locale),
                  _ModesPage(locale: locale),
                  _EventsPage(locale: locale),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                children: [
                  _Dots(count: _pageCount, current: _page),
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      key: const ValueKey('intro-next'),
                      onPressed: _next,
                      child: Text(
                        last
                            ? t(
                                locale,
                                ru: 'Начать',
                                kz: 'Бастау',
                                en: 'Get started',
                              )
                            : t(
                                locale,
                                ru: 'Далее',
                                kz: 'Әрі қарай',
                                en: 'Next',
                              ),
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

/// One intro page: an illustration-like badge, a title and text, plus
/// optional extra content. Scrolls when the text doesn't fit (large
/// system font on a small phone).
class _IntroPage extends StatelessWidget {
  const _IntroPage({
    required this.badge,
    required this.title,
    this.text,
    this.extra,
  });

  final Widget badge;
  final String title;
  final String? text;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    final textTheme = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              badge,
              const SizedBox(height: AppSpacing.xl),
              Text(
                title,
                textAlign: TextAlign.center,
                style: textTheme.titleLarge?.copyWith(
                  fontSize: 26,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              if (text != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  text!,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyLarge?.copyWith(
                    color: colors.textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
              if (extra != null) ...[
                const SizedBox(height: AppSpacing.lg),
                extra!,
              ],
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}

/// A large soft gold circle with an icon — the pages' only illustration.
class _Badge extends StatelessWidget {
  const _Badge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    return Container(
      width: 112,
      height: 112,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.goldPrimary.withValues(alpha: 0.12),
      ),
      child: Icon(icon, size: 52, color: colors.goldPrimary),
    );
  }
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage({required this.locale});

  final AppLocale locale;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    return _IntroPage(
      badge: Column(
        children: [
          RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                fontSize: 34,
                letterSpacing: 1.5,
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
          const SizedBox(height: AppSpacing.xl),
          const _Badge(icon: Icons.celebration_rounded),
        ],
      ),
      title: t(
        locale,
        ru: 'Всё для вашего мероприятия — в одном приложении',
        kz: 'Іс-шараңызға қажеттінің бәрі — бір қосымшада',
        en: 'Everything for your event — in one app',
      ),
      text: t(
        locale,
        ru:
            'Находите рестораны, ведущих, фотографов, шоу-программы '
            'и другие услуги для вашего события.',
        kz:
            'Мейрамханаларды, жүргізушілерді, фотографтарды, '
            'шоу-бағдарламаларды және басқа қызметтерді табыңыз.',
        en:
            'Find restaurants, hosts, photographers, shows and other '
            'services for your event.',
      ),
    );
  }
}

class _ModesPage extends StatelessWidget {
  const _ModesPage({required this.locale});

  final AppLocale locale;

  @override
  Widget build(BuildContext context) {
    return _IntroPage(
      badge: const _Badge(icon: Icons.swap_horiz_rounded),
      title: t(
        locale,
        ru: 'Один аккаунт — два режима',
        kz: 'Бір аккаунт — екі режим',
        en: 'One account, two modes',
      ),
      extra: Column(
        children: [
          _ModeRow(
            icon: Icons.celebration_rounded,
            title: t(
              locale,
              ru: 'Для мероприятия',
              kz: 'Іс-шара үшін',
              en: 'For an event',
            ),
            text: t(
              locale,
              ru:
                  'Ищите услуги, собирайте свой праздник и управляйте '
                  'выбранными предложениями.',
              kz:
                  'Қызметтерді іздеңіз, мерекеңізді жинаңыз және '
                  'таңдалған ұсыныстарды басқарыңыз.',
              en:
                  'Find services, plan your celebration and manage the '
                  'offers you’ve chosen.',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _ModeRow(
            icon: Icons.business_center_rounded,
            gold: true,
            title: t(
              locale,
              ru: 'Для бизнеса',
              kz: 'Бизнес үшін',
              en: 'For business',
            ),
            text: t(
              locale,
              ru:
                  'Размещайте свои услуги, получайте заявки и управляйте '
                  'своим профилем.',
              kz:
                  'Қызметтеріңізді орналастырыңыз, өтінімдер алыңыз және '
                  'профиліңізді басқарыңыз.',
              en: 'List your services, get requests and manage your profile.',
            ),
          ),
        ],
      ),
    );
  }
}

/// A compact mode description on the second page — the same two roles,
/// told apart the same way as on the mode choice (neutral vs gold).
class _ModeRow extends StatelessWidget {
  const _ModeRow({
    required this.icon,
    required this.title,
    required this.text,
    this.gold = false,
  });

  final IconData icon;
  final String title;
  final String text;
  final bool gold;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    final textTheme = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: gold
            ? colors.surface
            : Color.alphaBlend(
                colors.goldPrimary.withValues(alpha: 0.035),
                colors.surface,
              ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colors.border.withValues(alpha: colors.border.a * 0.5),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D1A1611),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: gold
                    ? colors.goldPrimary.withValues(alpha: 0.18)
                    : colors.textPrimary.withValues(alpha: 0.06),
              ),
              child: Icon(
                icon,
                size: 20,
                color: gold ? colors.goldPrimary : colors.textSecondary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: gold ? colors.goldSoft : colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    text,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                      height: 1.35,
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

class _EventsPage extends StatelessWidget {
  const _EventsPage({required this.locale});

  final AppLocale locale;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    return _IntroPage(
      badge: const _Badge(icon: Icons.event_available_rounded),
      title: t(
        locale,
        ru: 'Создавайте события проще',
        kz: 'Іс-шараларды оңай ұйымдастырыңыз',
        en: 'Plan events more easily',
      ),
      text: t(
        locale,
        ru:
            'Выбирайте город, сравнивайте предложения, сохраняйте '
            'понравившиеся услуги и собирайте всё необходимое для вашего '
            'мероприятия в одном месте.',
        kz:
            'Қаланы таңдаңыз, ұсыныстарды салыстырыңыз, ұнаған '
            'қызметтерді сақтаңыз және іс-шараңызға қажеттінің бәрін бір '
            'жерге жинаңыз.',
        en:
            'Choose your city, compare offers, save the services you like '
            'and gather everything for your event in one place.',
      ),
      // The icon sits inline at the start of the note, so it stays with
      // the text when the text wraps.
      extra: Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xxs),
                child: Icon(
                  Icons.swap_horiz_rounded,
                  size: 18,
                  color: colors.goldSoft,
                ),
              ),
            ),
            TextSpan(
              text: t(
                locale,
                ru: 'Переключаться между режимами можно в любой момент.',
                kz: 'Режимдер арасында кез келген уақытта ауыса аласыз.',
                en: 'You can switch between modes at any time.',
              ),
            ),
          ],
        ),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: colors.goldSoft,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Page dots: the current one a short gold pill, the rest small circles.
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            key: ValueKey('intro-dot-$i'),
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == current ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == current
                  ? colors.goldPrimary
                  : colors.textPrimary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}

/// The same language sheet as Home's globe button, so a Kazakh or English
/// speaker can switch before reading on.
class _LanguageButton extends StatelessWidget {
  const _LanguageButton({required this.locale});

  final AppLocale locale;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    return Semantics(
      button: true,
      label: t(
        locale,
        ru: 'Язык интерфейса: ${localeNativeName(locale)}',
        kz: 'Интерфейс тілі: ${localeNativeName(locale)}',
        en: 'Interface language: ${localeNativeName(locale)}',
      ),
      excludeSemantics: true,
      child: Material(
        color: colors.surface,
        shape: const StadiumBorder(),
        child: InkWell(
          key: const ValueKey('intro-language'),
          customBorder: const StadiumBorder(),
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => const LocaleSheet(),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.language_rounded,
                  size: 18,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  localeNativeName(locale),
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: colors.textPrimary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
