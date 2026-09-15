import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../core/utils/format.dart';
import '../../domain/manager_chat/manager_chat_context.dart';
import '../../models/manager_conversation.dart';
import '../../models/manager_message.dart';
import '../../state/auth_provider.dart';
import '../../state/locale_provider.dart';
import '../../state/manager_chat_provider.dart';
import '../../widgets/app_error_view.dart';
import '../../widgets/app_loader.dart';
import '../auth/login_screen.dart';

const _suggestionChips = [
  (
    ru: 'Подобрать услуги',
    kz: 'Қызметтерді таңдау',
    text: (
      ru: 'Помогите подобрать услуги для нашего мероприятия',
      kz: 'Іс-шарамызға қызметтерді таңдауға көмектесіңіз',
    ),
  ),
  (
    ru: 'Рассчитать стоимость',
    kz: 'Құнын есептеу',
    text: (
      ru: 'Подскажите, пожалуйста, примерную стоимость',
      kz: 'Болжамды құнын айтып жіберіңізші',
    ),
  ),
  (
    ru: 'Свободна ли дата?',
    kz: 'Күн бос па?',
    text: (
      ru: 'Подскажите, свободна ли нужная нам дата?',
      kz: 'Бізге керек күн бос па, айтып жіберіңізші?',
    ),
  ),
  (
    ru: 'Вопрос по услуге',
    kz: 'Қызмет туралы сұрақ',
    text: (ru: 'У меня вопрос по услуге', kz: 'Қызмет бойынша сұрағым бар'),
  ),
];

/// «Спросить менеджера» — a real two-way authenticated thread (brief
/// section 1), reusing exactly the same finds-or-creates-by-context
/// backend behavior `FloatingManagerWidget.jsx` relies on: opening this
/// screen with the same event/listing context again continues the one
/// existing conversation rather than starting a new one. Deliberately a
/// separate feature from Event comments (see `ManagerConversation`'s own
/// doc comment) — never routed anywhere near that thread.
class ManagerChatScreen extends ConsumerWidget {
  const ManagerChatScreen({
    super.key,
    this.chatContext = const ManagerChatContext(),
  });

  final ManagerChatContext chatContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final authState = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          t(locale, ru: 'Менеджер MEREYTOI', kz: 'MEREYTOI менеджері'),
        ),
      ),
      body: switch (authState) {
        AuthInitial() || AuthLoading() => const AppLoader(),
        AuthUnauthenticated() => _LoginPrompt(locale: locale),
        AuthAuthenticated() => _ChatBody(
          chatContext: chatContext,
          locale: locale,
        ),
      },
    );
  }
}

class _LoginPrompt extends StatelessWidget {
  const _LoginPrompt({required this.locale});

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
                ru: 'Войдите, чтобы написать менеджеру',
                kz: 'Менеджерге жазу үшін кіріңіз',
              ),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const LoginScreen())),
              child: Text(t(locale, ru: 'Войти', kz: 'Кіру')),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBody extends ConsumerStatefulWidget {
  const _ChatBody({required this.chatContext, required this.locale});

  final ManagerChatContext chatContext;
  final AppLocale locale;

  @override
  ConsumerState<_ChatBody> createState() => _ChatBodyState();
}

class _ChatBodyState extends ConsumerState<_ChatBody> {
  final _controller = TextEditingController();
  bool _sending = false;
  String? _sendError;

  ManagerChatKey get _key => (
    eventId: widget.chatContext.eventId,
    listingId: widget.chatContext.listingId,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    final body = text.trim();
    if (body.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _sendError = null;
    });
    _controller.clear();
    try {
      await ref
          .read(managerChatProvider(_key).notifier)
          .sendMessage(
            body,
            firstMessagePrefix: restaurantContextText(widget.chatContext),
          );
    } catch (err) {
      if (mounted) {
        setState(() {
          _controller.text = body;
          _sendError = apiErrorMessage(widget.locale, err);
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = widget.locale;
    final chatAsync = ref.watch(managerChatProvider(_key));

    return chatAsync.when(
      loading: () => const AppLoader(),
      error: (err, _) => Center(
        child: AppErrorView(
          message: apiErrorMessage(locale, err),
          locale: locale,
          onRetry: () => ref.read(managerChatProvider(_key).notifier).refresh(),
        ),
      ),
      data: (data) {
        final messages = data.messages;
        return Column(
          children: [
            _ContextCard(
              chatContext: widget.chatContext,
              conversation: data.conversation,
              locale: locale,
            ),
            Expanded(
              child: messages.isEmpty
                  ? _EmptySuggestions(
                      locale: locale,
                      onPick: (text) => _controller.text = text,
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      itemCount: messages.length,
                      itemBuilder: (context, i) =>
                          _MessageBubble(message: messages[i]),
                    ),
            ),
            if (_sendError != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Text(
                  _sendError!,
                  style: TextStyle(
                    color: context.mereytoiColors.error,
                    fontSize: 12.5,
                  ),
                ),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.xs,
                  AppSpacing.md,
                  AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 1000,
                        buildCounter:
                            (
                              _, {
                              required currentLength,
                              required isFocused,
                              maxLength,
                            }) => null,
                        decoration: InputDecoration(
                          hintText: t(
                            locale,
                            ru: 'Написать сообщение…',
                            kz: 'Хабарлама жазу…',
                          ),
                        ),
                        onSubmitted: _send,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    IconButton.filled(
                      onPressed: _sending
                          ? null
                          : () => _send(_controller.text),
                      icon: _sending
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: context.mereytoiColors.onGold,
                              ),
                            )
                          : const Icon(Icons.send_rounded, size: 18),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ContextCard extends StatelessWidget {
  const _ContextCard({
    required this.chatContext,
    required this.conversation,
    required this.locale,
  });

  final ManagerChatContext chatContext;
  final ManagerConversation? conversation;
  final AppLocale locale;

  @override
  Widget build(BuildContext context) {
    // The conversation's own nested event/listing (once it exists
    // server-side) is authoritative; before a first round-trip, the
    // caller's own already-known context is the fallback — same priority
    // FloatingManagerWidget.jsx uses for ctxEvent/ctxListing.
    final eventTitle = conversation?.event?.title ?? chatContext.eventTitle;
    final listingName =
        conversation?.listing?.name(locale) ?? chatContext.listingName;
    final listingPrice =
        conversation?.listing?.price ?? chatContext.listingPrice;

    if (eventTitle == null && listingName == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        0,
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: context.mereytoiColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (eventTitle != null)
            Text(
              eventTitle,
              style: Theme.of(context).textTheme.titleSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          if (listingName != null) ...[
            if (eventTitle != null) const SizedBox(height: 2),
            Text(
              listingPrice != null && listingPrice > 0
                  ? '$listingName · ${formatPrice(listingPrice)}'
                  : listingName,
              style: Theme.of(context).textTheme.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (chatContext.menuName != null) ...[
            const SizedBox(height: 2),
            Wrap(
              spacing: AppSpacing.xxs,
              children: [
                if (chatContext.hallName != null)
                  _MiniTag(chatContext.hallName!),
                _MiniTag(chatContext.menuName!),
                if (chatContext.guestCount != null &&
                    chatContext.guestCount! > 0)
                  _MiniTag(
                    '${chatContext.guestCount} ${t(locale, ru: "гостей", kz: "қонақ")}',
                  ),
                if (chatContext.estimatedTotal != null &&
                    chatContext.estimatedTotal! > 0)
                  _MiniTag('≈${formatPrice(chatContext.estimatedTotal!)}'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: context.mereytoiColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _EmptySuggestions extends StatelessWidget {
  const _EmptySuggestions({required this.locale, required this.onPick});

  final AppLocale locale;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t(
                locale,
                ru: 'Задайте вопрос — менеджер ответит в ближайшее время.',
                kz: 'Сұрағыңызды қойыңыз — менеджер жақын арада жауап береді.',
              ),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpacing.xxs,
              runSpacing: AppSpacing.xxs,
              children: _suggestionChips
                  .map(
                    (chip) => ActionChip(
                      label: Text(t(locale, ru: chip.ru, kz: chip.kz)),
                      onPressed: () =>
                          onPick(t(locale, ru: chip.text.ru, kz: chip.text.kz)),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ManagerMessage message;

  @override
  Widget build(BuildContext context) {
    final fromManager = message.isFromManager;
    return Align(
      alignment: fromManager ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        margin: const EdgeInsets.only(bottom: AppSpacing.xs),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: fromManager
              ? context.mereytoiColors.surface
              : context.mereytoiColors.goldPrimary.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message.body, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 2),
            Text(
              _timeLabel(message.createdAt),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: context.mereytoiColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _timeLabel(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
