import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../domain/manager_chat/manager_chat_context.dart';
import '../../models/manager_conversation.dart';
import '../../state/auth_provider.dart';
import '../../state/chat_unread_provider.dart';
import '../../state/locale_provider.dart';
import '../../state/manager_chat_provider.dart';
import '../../state/provider_chat_provider.dart';
import '../../widgets/app_icon_badge.dart';
import '../../widgets/app_loader.dart';
import '../auth/login_screen.dart';
import '../manager_chat/manager_chat_screen.dart';
import '../provider_chat/provider_chat_list_screen.dart';

/// «Сообщения» — the global chat hub opened from [ChatFab]: every manager
/// conversation (`GET /api/manager-chat`) and every provider conversation
/// (`GET /api/provider-chat`) in one place. Purely a hub — each row opens
/// the existing [ManagerChatScreen]/ProviderChatScreen by conversationId;
/// there is no second chat implementation here. A guest gets a sign-in
/// prompt and no API call at all (never a 401).
class MessagesScreen extends ConsumerWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final authState = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          t(locale, ru: 'Сообщения', kz: 'Хабарламалар', en: 'Messages'),
        ),
      ),
      body: switch (authState) {
        AuthInitial() || AuthLoading() => const AppLoader(),
        AuthUnauthenticated() => _GuestPrompt(locale: locale),
        AuthAuthenticated(:final user) => _Hub(
          locale: locale,
          myUserId: user.id,
        ),
      },
    );
  }
}

class _GuestPrompt extends StatelessWidget {
  const _GuestPrompt({required this.locale});

  final AppLocale locale;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppIconBadge(icon: Icons.chat_bubble_outline_rounded),
            const SizedBox(height: AppSpacing.md),
            Text(
              t(
                locale,
                ru: 'Войдите, чтобы видеть сообщения',
                kz: 'Хабарламаларды көру үшін кіріңіз',
                en: 'Sign in to see your messages',
              ),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              t(
                locale,
                ru: 'Здесь будут переписки с менеджером MEREYTOI и услугодателями.',
                kz: 'Мұнда MEREYTOI менеджерімен және қызмет көрсетушілермен хат алмасу болады.',
                en: 'Your conversations with the MEREYTOI manager and service providers will appear here.',
              ),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const LoginScreen())),
              child: Text(t(locale, ru: 'Войти', kz: 'Кіру', en: 'Sign in')),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hub extends ConsumerWidget {
  const _Hub({required this.locale, required this.myUserId});

  final AppLocale locale;
  final int myUserId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final managerAsync = ref.watch(managerConversationsProvider);
    final providerAsync = ref.watch(providerConversationsProvider);

    Future<void> refresh() async {
      refreshChatLists(ref);
      await Future.wait([
        ref.read(managerConversationsProvider.future),
        ref.read(providerConversationsProvider.future),
      ]).catchError((_) => const <List<Object>>[]);
    }

    return RefreshIndicator(
      color: context.mereytoiColors.goldPrimary,
      backgroundColor: context.mereytoiColors.surfaceElevated,
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        children: [
          _SectionTitle(
            t(
              locale,
              ru: 'Менеджер MEREYTOI',
              kz: 'MEREYTOI менеджері',
              en: 'MEREYTOI manager',
            ),
          ),
          ...managerAsync.when(
            loading: () => [const _SectionLoader()],
            error: (err, _) => [
              _SectionError(
                message: apiErrorMessage(locale, err),
                locale: locale,
                onRetry: () => ref.invalidate(managerConversationsProvider),
              ),
            ],
            data: (list) => list.isEmpty
                ? [_ManagerEmpty(locale: locale)]
                : [
                    for (final s in list) ...[
                      _ManagerConversationRow(summary: s, locale: locale),
                      const SizedBox(height: AppSpacing.xs),
                    ],
                  ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _SectionTitle(
            t(
              locale,
              ru: 'Услугодатели',
              kz: 'Қызмет көрсетушілер',
              en: 'Service providers',
            ),
          ),
          ...providerAsync.when(
            loading: () => [const _SectionLoader()],
            error: (err, _) => [
              _SectionError(
                message: apiErrorMessage(locale, err),
                locale: locale,
                onRetry: () => ref.invalidate(providerConversationsProvider),
              ),
            ],
            data: (list) => list.isEmpty
                ? [
                    _EmptyNote(
                      t(
                        locale,
                        ru: 'Пока нет переписок с услугодателями',
                        kz: 'Қызмет көрсетушілермен әзірге хат алмасу жоқ',
                        en: 'No conversations with providers yet',
                      ),
                    ),
                  ]
                : [
                    for (final s in list) ...[
                      ProviderConversationRow(
                        summary: s,
                        myUserId: myUserId,
                        locale: locale,
                        onReturn: () => refreshChatLists(ref),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                    ],
                  ],
          ),
        ],
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
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: context.mereytoiColors.goldPrimary,
        ),
      ),
    );
  }
}

class _SectionLoader extends StatelessWidget {
  const _SectionLoader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.sm,
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

class _SectionError extends StatelessWidget {
  const _SectionError({
    required this.message,
    required this.locale,
    required this.onRetry,
  });

  final String message;
  final AppLocale locale;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.mereytoiColors.error,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: Text(
              t(locale, ru: 'Повторить', kz: 'Қайталау', en: 'Retry'),
            ),
          ),
        ],
      ),
    );
  }
}

/// No manager conversation yet — offer to start the general one, the same
/// `ManagerChatScreen()` Profile's «Написать менеджеру» opens.
class _ManagerEmpty extends ConsumerWidget {
  const _ManagerEmpty({required this.locale});

  final AppLocale locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t(
              locale,
              ru: 'Пока нет обращений к менеджеру',
              kz: 'Менеджерге әзірге өтініш жоқ',
              en: 'No conversations with the manager yet',
            ),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          OutlinedButton.icon(
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ManagerChatScreen()),
              );
              refreshChatLists(ref);
            },
            icon: const Icon(Icons.support_agent_rounded, size: 18),
            label: Text(
              t(
                locale,
                ru: 'Написать менеджеру',
                kz: 'Менеджерге жазу',
                en: 'Message the manager',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ManagerConversationRow extends ConsumerWidget {
  const _ManagerConversationRow({required this.summary, required this.locale});

  final ManagerConversationSummary summary;
  final AppLocale locale;

  /// What the thread is about: the service, else the event, else a
  /// general question — the same context the chat's own header shows.
  String _title() {
    final conv = summary.conversation;
    final listing = conv.listing;
    if (listing != null) {
      final name = locale == AppLocale.kz ? listing.nameKz : listing.nameRu;
      if (name.isNotEmpty) return name;
    }
    final eventTitle = conv.event?.title;
    if (eventTitle != null && eventTitle.isNotEmpty) return eventTitle;
    return t(
      locale,
      ru: 'Общий вопрос',
      kz: 'Жалпы сұрақ',
      en: 'General question',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conv = summary.conversation;
    final colors = context.mereytoiColors;

    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ManagerChatScreen(
                conversationId: conv.id,
                chatContext: ManagerChatContext(
                  eventId: conv.eventId,
                  listingId: conv.listingId,
                ),
              ),
            ),
          );
          refreshChatLists(ref);
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              const AppIconBadge(
                icon: Icons.support_agent_rounded,
                size: 44,
                iconSize: 22,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _title(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        if (summary.lastMessageAt != null)
                          Text(
                            messageTimeLabel(summary.lastMessageAt!),
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: colors.textMuted),
                          ),
                      ],
                    ),
                    if (summary.lastMessageBody != null)
                      Text(
                        summary.lastMessageBody!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              if (summary.unreadCount > 0) ...[
                const SizedBox(width: AppSpacing.xs),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: colors.goldPrimary,
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                  ),
                  child: Text(
                    '${summary.unreadCount}',
                    style: TextStyle(
                      color: colors.onGold,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "14:05" for today, "25.09" otherwise — a list row only needs enough to
/// tell recent from older threads.
String messageTimeLabel(DateTime dt, {DateTime? now}) {
  final local = dt.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  if (local.year == today.year &&
      local.month == today.month &&
      local.day == today.day) {
    return '${two(local.hour)}:${two(local.minute)}';
  }
  return '${two(local.day)}.${two(local.month)}';
}
