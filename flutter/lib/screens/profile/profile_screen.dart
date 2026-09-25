import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../domain/event/event_status.dart';
import '../../models/user.dart';
import '../../state/auth_provider.dart';
import '../../state/categories_provider.dart';
import '../../state/event_providers.dart';
import '../../state/listings_provider.dart';
import '../../state/locale_provider.dart';
import '../../state/provider_provider.dart';
import '../../state/providers.dart';
import '../../state/theme_provider.dart';
import '../../widgets/app_card.dart';
import '../../widgets/theme_mode_sheet.dart';
import '../events/event_workspace_screen.dart';
import '../manager_chat/manager_chat_screen.dart';
import '../provider_chat/provider_chat_list_screen.dart';
import 'provider/my_services_screen.dart';
import 'provider/widgets/provider_profile_form_sheet.dart';
import 'restaurant_admin/restaurant_admin_list_screen.dart';

/// Brief section 3 — the account screen: identity, messenger/delivery
/// settings, "Мои мероприятия", logout. Every field/endpoint here is real
/// (`GET/PUT /api/auth/me`, `PUT /api/users/me/delivery-preference`,
/// `POST /api/users/me/telegram/link-token`) — nothing invented.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final authState = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(t(locale, ru: 'Профиль', kz: 'Профиль', en: 'Profile')),
      ),
      body: switch (authState) {
        AuthAuthenticated(:final user) => _ProfileBody(
          user: user,
          locale: locale,
        ),
        _ => Center(
          child: Text(
            t(
              locale,
              ru: 'Нужно войти',
              kz: 'Кіру керек',
              en: 'Sign-in required',
            ),
          ),
        ),
      },
    );
  }
}

class _ProfileBody extends ConsumerStatefulWidget {
  const _ProfileBody({required this.user, required this.locale});

  final User user;
  final AppLocale locale;

  @override
  ConsumerState<_ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends ConsumerState<_ProfileBody>
    with WidgetsBindingObserver {
  bool _mintingTelegram = false;
  bool _awaitingTelegramReturn = false;
  String? _telegramError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Linking happens async, via the bot's own webhook — the only
    // reliable moment to check "did it actually link?" is when the user
    // comes back from the Telegram app.
    if (state == AppLifecycleState.resumed && _awaitingTelegramReturn) {
      _awaitingTelegramReturn = false;
      ref.read(authProvider.notifier).refreshMe();
    }
  }

  Future<void> _connectTelegram() async {
    setState(() {
      _mintingTelegram = true;
      _telegramError = null;
    });
    try {
      final result = await ref
          .read(authServiceProvider)
          .mintTelegramLinkToken();
      if (!result.configured || result.linkUrl == null) {
        if (mounted) {
          setState(
            () => _telegramError = t(
              widget.locale,
              ru: 'Telegram сейчас недоступен',
              kz: 'Telegram қазір қолжетімсіз',
              en: 'Telegram is currently unavailable',
            ),
          );
        }
        return;
      }
      _awaitingTelegramReturn = true;
      await launchUrl(
        Uri.parse(result.linkUrl!),
        mode: LaunchMode.externalApplication,
      );
    } catch (err) {
      if (mounted) {
        setState(() => _telegramError = apiErrorMessage(widget.locale, err));
      }
    } finally {
      if (mounted) setState(() => _mintingTelegram = false);
    }
  }

  Future<void> _setDeliveryChannel(String channel) async {
    try {
      await ref.read(authProvider.notifier).updateDeliveryPreference(channel);
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiErrorMessage(widget.locale, err))),
        );
      }
    }
  }

  Future<void> _logout() async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (sheetContext) => _LogoutConfirmSheet(locale: widget.locale),
    );
    if (confirmed == true) {
      await ref.read(authProvider.notifier).logout();
      if (mounted) Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = widget.locale;
    final user = widget.user;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        // ---- Аккаунт ----
        AppCard(
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: context.mereytoiColors.surfaceSoft,
                child: Text(
                  user.name.isNotEmpty
                      ? user.name.substring(0, 1).toUpperCase()
                      : '?',
                  style: TextStyle(
                    color: context.mereytoiColors.goldPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (user.email.isNotEmpty)
                      Text(
                        user.email,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    if (user.phone.isNotEmpty)
                      Text(
                        user.phone,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => _EditProfileSheet(user: user, locale: locale),
                ),
                icon: Icon(
                  Icons.edit_outlined,
                  size: 18,
                  color: context.mereytoiColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // ---- Мессенджеры ----
        _SectionTitle(
          t(locale, ru: 'Мессенджеры', kz: 'Мессенджерлер', en: 'Messengers'),
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    user.telegramLinked == true
                        ? Icons.check_circle_rounded
                        : Icons.telegram,
                    size: 18,
                    color: user.telegramLinked == true
                        ? context.mereytoiColors.success
                        : context.mereytoiColors.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      user.telegramLinked == true
                          ? t(
                              locale,
                              ru: 'Telegram подключён',
                              kz: 'Telegram қосылған',
                              en: 'Telegram connected',
                            )
                          : t(
                              locale,
                              ru: 'Telegram не подключён',
                              kz: 'Telegram қосылмаған',
                              en: 'Telegram not connected',
                            ),
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                  if (user.telegramLinked != true)
                    TextButton(
                      onPressed: _mintingTelegram ? null : _connectTelegram,
                      child: _mintingTelegram
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              t(
                                locale,
                                ru: 'Подключить',
                                kz: 'Қосу',
                                en: 'Connect',
                              ),
                            ),
                    ),
                ],
              ),
              if (_telegramError != null) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  _telegramError!,
                  style: TextStyle(
                    color: context.mereytoiColors.error,
                    fontSize: 12.5,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              Text(
                t(
                  locale,
                  ru: 'Куда присылать ссылки',
                  kz: 'Сілтемелерді қайда жіберу',
                  en: 'Where to send links',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Wrap(
                spacing: AppSpacing.xxs,
                children: [
                  ChoiceChip(
                    label: const Text('WhatsApp'),
                    selected: user.preferredDeliveryChannel == 'whatsapp',
                    onSelected: (_) => _setDeliveryChannel('whatsapp'),
                  ),
                  ChoiceChip(
                    label: const Text('Telegram'),
                    selected: user.preferredDeliveryChannel == 'telegram',
                    onSelected: (_) => _setDeliveryChannel('telegram'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // ---- Оформление ----
        _SectionTitle(
          t(locale, ru: 'Оформление', kz: 'Көрініс', en: 'Appearance'),
        ),
        Consumer(
          builder: (context, ref, _) {
            final mode = ref.watch(themeModeProvider);
            return AppCard(
              padding: EdgeInsets.zero,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const ThemeModeSheet(),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      Icon(
                        Icons.palette_outlined,
                        size: 18,
                        color: context.mereytoiColors.textSecondary,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          t(
                            locale,
                            ru: 'Тема оформления',
                            kz: 'Көрініс тақырыбы',
                            en: 'Theme',
                          ),
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                      Text(
                        themeModeLabel(locale, mode),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: context.mereytoiColors.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.lg),

        // ---- Поддержка — Этап 10Б-53: the only entry point into Manager
        // Chat that doesn't depend on already being on a specific
        // service/restaurant page (those get their own context-aware
        // `AskManagerButton`; this one opens a plain, contextless thread —
        // the same shape `booking_success_screen.dart`'s own "Связаться с
        // менеджером" button already uses). ----
        _SectionTitle(t(locale, ru: 'Поддержка', kz: 'Қолдау', en: 'Support')),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              InkWell(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadius.lg),
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ManagerChatScreen()),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      Icon(
                        Icons.support_agent_rounded,
                        size: 18,
                        color: context.mereytoiColors.textSecondary,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          t(
                            locale,
                            ru: 'Написать менеджеру',
                            kz: 'Менеджерге жазу',
                            en: 'Message the manager',
                          ),
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: context.mereytoiColors.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: context.mereytoiColors.divider),
              // Этап 11G — a customer's own entry point into the provider
              // dialogs list, reachable without a provider profile (unlike
              // "Сообщения от клиентов" below, which only ever shows for an
              // actual provider). Pushes the exact same
              // ProviderChatListScreen — GET /api/provider-chat already
              // returns every conversation the caller is a participant of
              // on either side.
              InkWell(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(AppRadius.lg),
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ProviderChatListScreen(),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 18,
                        color: context.mereytoiColors.textSecondary,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          t(
                            locale,
                            ru: 'Переписка с услугодателями',
                            kz: 'Қызмет көрсетушілермен хат алысу',
                            en: 'Messages with providers',
                          ),
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: context.mereytoiColors.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // ---- Мои рестораны — server-side scoped by ListingManager, not
        // by `user.isAdmin` (see RestaurantAdminListScreen's own doc
        // comment): a global admin gets a permanent "Управление
        // ресторанами" entry that reaches every listing; anyone else only
        // sees this section at all once GET /api/users/me/listings
        // actually returns at least one assigned listing — never a dead
        // end for a user who manages nothing. ----
        if (user.isAdmin)
          _RestaurantsEntrySection(
            sectionTitle: t(
              locale,
              ru: 'Мои услуги',
              kz: 'Менің қызметтерім',
              en: 'My services',
            ),
            screenTitle: t(
              locale,
              ru: 'Управление ресторанами',
              kz: 'Мейрамханаларды басқару',
              en: 'Manage restaurants',
            ),
          )
        else
          Consumer(
            builder: (context, ref, _) {
              final myListingsAsync = ref.watch(myListingsProvider);
              final categoriesAsync = ref.watch(categoriesProvider);
              // Этап 11E QA finding: myListingsProvider returns every
              // category a caller manages, not just venues (see its own
              // doc comment) — a provider who only self-serve-created a
              // non-restaurant service (Этап 11's own MyServicesScreen)
              // must not see a "Мои рестораны" entry that would open
              // RestaurantManageScreen (halls/menus tabs) on a listing
              // that has neither.
              final venueCategoryIds = categoriesAsync.maybeWhen(
                data: (categories) => categories
                    .where((c) => c.slug == 'venues')
                    .map((c) => c.id)
                    .toSet(),
                orElse: () => const <int>{},
              );
              final hasOwn = myListingsAsync.maybeWhen(
                data: (listings) =>
                    listings.any((l) => venueCategoryIds.contains(l.categoryId)),
                orElse: () => false,
              );
              if (!hasOwn) return const SizedBox.shrink();
              final restaurantsTitle = t(
                locale,
                ru: 'Мои рестораны',
                kz: 'Менің мейрамханаларым',
                en: 'My restaurants',
              );
              return _RestaurantsEntrySection(
                sectionTitle: restaurantsTitle,
                screenTitle: restaurantsTitle,
              );
            },
          ),

        // ---- Услугодатель — Этап 11 "Provider Marketplace". Deliberately
        // separate from the Мои рестораны/"Мои услуги" (admin) section
        // above: that one is restaurant/venue management via
        // ListingManager directly; this is the new self-serve provider
        // profile + non-venues services flow (see
        // backend/internal/models/provider.go's own doc comment on why
        // it's a distinct, optional profile rather than a Role). Hidden
        // for a global admin — admin already manages every listing
        // regardless, "стать услугодателем" has no meaning for that
        // account. ----
        if (!user.isAdmin) const _ProviderEntrySection(),

        // ---- Мои мероприятия ----
        _SectionTitle(
          t(
            locale,
            ru: 'Мои мероприятия',
            kz: 'Менің іс-шараларым',
            en: 'My events',
          ),
        ),
        Consumer(
          builder: (context, ref, _) {
            final eventsAsync = ref.watch(eventsProvider);
            return eventsAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
              data: (events) {
                if (events.isEmpty) {
                  return AppCard(
                    child: Text(
                      t(
                        locale,
                        ru: 'У вас пока нет мероприятий',
                        kz: 'Сізде әлі іс-шара жоқ',
                        en: 'You don\'t have any events yet',
                      ),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  );
                }
                return Column(
                  children: events
                      .take(5)
                      .map(
                        (event) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: GestureDetector(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    EventWorkspaceScreen(eventId: event.id),
                              ),
                            ),
                            child: AppCard(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: AppSpacing.sm,
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    eventTypeEmoji(event.type),
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  Expanded(
                                    child: Text(
                                      event.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyLarge,
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    size: 18,
                                    color: context.mereytoiColors.textMuted,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            );
          },
        ),
        const SizedBox(height: AppSpacing.lg),

        OutlinedButton(
          onPressed: _logout,
          style: OutlinedButton.styleFrom(
            foregroundColor: context.mereytoiColors.error,
          ),
          child: Text(t(locale, ru: 'Выйти', kz: 'Шығу', en: 'Sign out')),
        ),
      ],
    );
  }
}

/// Section title + the single "open restaurant management" card — shared
/// between the always-on global-admin entry point and the conditional
/// owner/manager one, which differ only in copy, never in behavior (both
/// open the same [RestaurantAdminListScreen], scoped server-side by
/// `GET /api/users/me/listings`).
class _RestaurantsEntrySection extends StatelessWidget {
  const _RestaurantsEntrySection({
    required this.sectionTitle,
    required this.screenTitle,
  });

  final String sectionTitle;
  final String screenTitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(sectionTitle),
        AppCard(
          padding: EdgeInsets.zero,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => RestaurantAdminListScreen(title: screenTitle),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Icon(
                    Icons.storefront_outlined,
                    size: 18,
                    color: context.mereytoiColors.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      screenTitle,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: context.mereytoiColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

/// "Стать услугодателем" (no profile yet) → "Профиль услугодателя" + "Мои
/// услуги" (profile exists) — Этап 11 brief section 3. Silently collapses
/// on loading/error rather than blocking the rest of the profile screen —
/// this is an optional, secondary section, same "don't gate the whole
/// screen on it" treatment the Мои мероприятия block above already gives
/// its own eventsAsync.
class _ProviderEntrySection extends ConsumerWidget {
  const _ProviderEntrySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final providerAsync = ref.watch(providerProfileProvider);

    return providerAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (provider) {
        if (provider == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionTitle(
                t(
                  locale,
                  ru: 'Услугодатель',
                  kz: 'Қызмет көрсетуші',
                  en: 'Provider',
                ),
              ),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t(
                        locale,
                        ru: 'Предлагаете услуги для тоев?',
                        kz: 'Той қызметтерін ұсынасыз ба?',
                        en: 'Do you offer event services?',
                      ),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      t(
                        locale,
                        ru: 'Заполните короткий профиль и добавьте свою услугу в каталог MEREYTOI.',
                        kz: 'Қысқаша профильді толтырып, қызметіңізді MEREYTOI каталогына қосыңыз.',
                        en: 'Fill in a short profile and add your service to the MEREYTOI catalog.',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    ElevatedButton(
                      onPressed: () => openProviderProfileFormSheet(context),
                      child: Text(
                        t(
                          locale,
                          ru: 'Стать услугодателем',
                          kz: 'Қызмет көрсетуші болу',
                          en: 'Become a provider',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(provider.displayName),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  InkWell(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppRadius.lg),
                    ),
                    onTap: () => openProviderProfileFormSheet(
                      context,
                      existing: provider,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Row(
                        children: [
                          Icon(
                            Icons.storefront_outlined,
                            color: context.mereytoiColors.goldPrimary,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              t(
                                locale,
                                ru: 'Профиль услугодателя',
                                kz: 'Қызмет көрсетуші профилі',
                                en: 'Provider profile',
                              ),
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: context.mereytoiColors.textMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Divider(height: 1, color: context.mereytoiColors.divider),
                  InkWell(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MyServicesScreen(),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Row(
                        children: [
                          Icon(
                            Icons.design_services_outlined,
                            color: context.mereytoiColors.goldPrimary,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              t(
                                locale,
                                ru: 'Мои услуги',
                                kz: 'Менің қызметтерім',
                                en: 'My services',
                              ),
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: context.mereytoiColors.textMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Divider(height: 1, color: context.mereytoiColors.divider),
                  // Этап 11G brief section 6 — "Сообщения от клиентов".
                  InkWell(
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(AppRadius.lg),
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ProviderChatListScreen(),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Row(
                        children: [
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            color: context.mereytoiColors.goldPrimary,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              t(
                                locale,
                                ru: 'Сообщения от клиентов',
                                kz: 'Клиенттерден хабарламалар',
                                en: 'Messages from customers',
                              ),
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: context.mereytoiColors.textMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: context.mereytoiColors.textSecondary,
        ),
      ),
    );
  }
}

class _LogoutConfirmSheet extends StatelessWidget {
  const _LogoutConfirmSheet({required this.locale});

  final AppLocale locale;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t(
                locale,
                ru: 'Выйти из аккаунта?',
                kz: 'Аккаунттан шығу керек пе?',
                en: 'Sign out of your account?',
              ),
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(t(locale, ru: 'Выйти', kz: 'Шығу', en: 'Sign out')),
            ),
            const SizedBox(height: AppSpacing.xs),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                t(locale, ru: 'Отмена', kz: 'Бас тарту', en: 'Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditProfileSheet extends ConsumerStatefulWidget {
  const _EditProfileSheet({required this.user, required this.locale});

  final User user;
  final AppLocale locale;

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  late final _nameController = TextEditingController(text: widget.user.name);
  late final _phoneController = TextEditingController(text: widget.user.phone);
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(authProvider.notifier)
          .updateProfile(name: name, phone: _phoneController.text.trim());
      if (mounted) Navigator.of(context).pop();
    } catch (err) {
      if (mounted) setState(() => _error = apiErrorMessage(widget.locale, err));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = widget.locale;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.mereytoiColors.surfaceElevated,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t(
                    locale,
                    ru: 'Редактировать профиль',
                    kz: 'Профильді өңдеу',
                    en: 'Edit profile',
                  ),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: t(locale, ru: 'Имя', kz: 'Атыңыз', en: 'Name'),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: t(
                      locale,
                      ru: 'Телефон',
                      kz: 'Телефон',
                      en: 'Phone',
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: context.mereytoiColors.error,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: context.mereytoiColors.onGold,
                            ),
                          )
                        : Text(
                            t(
                              locale,
                              ru: 'Сохранить',
                              kz: 'Сақтау',
                              en: 'Save',
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
