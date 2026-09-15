import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../domain/event/event_status.dart';
import '../../models/user.dart';
import '../../state/auth_provider.dart';
import '../../state/event_providers.dart';
import '../../state/locale_provider.dart';
import '../../state/providers.dart';
import '../../state/theme_provider.dart';
import '../../widgets/app_card.dart';
import '../events/event_workspace_screen.dart';

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
        title: Text(t(locale, ru: 'Профиль', kz: 'Профиль')),
      ),
      body: switch (authState) {
        AuthAuthenticated(:final user) => _ProfileBody(
          user: user,
          locale: locale,
        ),
        _ => Center(
          child: Text(t(locale, ru: 'Нужно войти', kz: 'Кіру керек')),
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
        _SectionTitle(t(locale, ru: 'Мессенджеры', kz: 'Мессенджерлер')),
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
                            )
                          : t(
                              locale,
                              ru: 'Telegram не подключён',
                              kz: 'Telegram қосылмаған',
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
                          : Text(t(locale, ru: 'Подключить', kz: 'Қосу')),
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
        _SectionTitle(t(locale, ru: 'Оформление', kz: 'Көрініс')),
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
                  builder: (_) => const _ThemeModeSheet(),
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
                          ),
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                      Text(
                        _themeModeLabel(locale, mode),
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

        // ---- Мои мероприятия ----
        _SectionTitle(
          t(locale, ru: 'Мои мероприятия', kz: 'Менің іс-шараларым'),
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
          child: Text(t(locale, ru: 'Выйти', kz: 'Шығу')),
        ),
      ],
    );
  }
}

String _themeModeLabel(AppLocale locale, ThemeMode mode) {
  return switch (mode) {
    ThemeMode.system => t(locale, ru: 'Системная', kz: 'Жүйелік'),
    ThemeMode.light => t(locale, ru: 'Светлая', kz: 'Ашық'),
    ThemeMode.dark => t(locale, ru: 'Тёмная', kz: 'Қараңғы'),
  };
}

/// "Оформление" — Системная / Светлая / Тёмная (brief section 8). A plain
/// bottom sheet of radio-style tiles, the same mobile pattern the rest of
/// this app already uses for a single pick-one choice (see
/// `category_picker_sheet.dart`) rather than a segmented control, which
/// reads more like a desktop/web control at this width.
class _ThemeModeSheet extends ConsumerWidget {
  const _ThemeModeSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final current = ref.watch(themeModeProvider);
    final colors = context.mereytoiColors;

    return SafeArea(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t(locale, ru: 'Оформление', kz: 'Көрініс'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final mode in ThemeMode.values)
                _ThemeModeTile(
                  mode: mode,
                  label: _themeModeLabel(locale, mode),
                  icon: switch (mode) {
                    ThemeMode.system => Icons.brightness_auto_rounded,
                    ThemeMode.light => Icons.light_mode_rounded,
                    ThemeMode.dark => Icons.dark_mode_rounded,
                  },
                  selected: current == mode,
                  onTap: () {
                    ref.read(themeModeProvider.notifier).setMode(mode);
                    Navigator.of(context).pop();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeModeTile extends StatelessWidget {
  const _ThemeModeTile({
    required this.mode,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final ThemeMode mode;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? colors.goldPrimary : colors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: selected ? colors.textPrimary : colors.textSecondary,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (selected)
                Icon(Icons.check_rounded, size: 20, color: colors.goldPrimary),
            ],
          ),
        ),
      ),
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
              ),
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(t(locale, ru: 'Выйти', kz: 'Шығу')),
            ),
            const SizedBox(height: AppSpacing.xs),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(t(locale, ru: 'Отмена', kz: 'Бас тарту')),
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
                  t(locale, ru: 'Редактировать профиль', kz: 'Профильді өңдеу'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: t(locale, ru: 'Имя', kz: 'Атыңыз'),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: t(locale, ru: 'Телефон', kz: 'Телефон'),
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
                        : Text(t(locale, ru: 'Сохранить', kz: 'Сақтау')),
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
