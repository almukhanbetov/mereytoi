import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/api_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../core/utils/format.dart';
import '../../models/provider_conversation.dart';
import '../../models/provider_message.dart';
import '../../state/auth_provider.dart';
import '../../state/locale_provider.dart';
import '../../state/provider_chat_provider.dart';
import '../../widgets/app_error_view.dart';
import '../../widgets/app_loader.dart';
import '../../widgets/network_image_box.dart';
import '../auth/login_screen.dart';

/// «Написать услугодателю» — Этап 11G. A direct, authenticated thread with
/// one marketplace provider, deliberately separate from [ManagerChatScreen]
/// (see backend/internal/models/provider_chat.go's own doc comment): two
/// different channels, two different buttons on the same service page.
/// Structurally mirrors ManagerChatScreen closely (same bubble/autoscroll/
/// keyboard-safe/retry shape, brief section 5) — the two features are
/// parallel, not shared, since their backends are separate models.
class ProviderChatScreen extends ConsumerWidget {
  const ProviderChatScreen({
    super.key,
    required this.providerId,
    required this.peerName,
    this.peerAvatarUrl,
    this.listingId,
    this.listingName,
    this.listingPrice,
    this.conversationId,
  });

  /// Always the marketplace Provider's own id — the actual key the backend
  /// conversation is addressed by (`(customer_user_id, provider_id,
  /// listing_id)`), regardless of which side the viewer is on.
  final int providerId;

  /// The app-bar title/avatar — "the other side" from the *viewer's* own
  /// point of view: the provider's own name/avatar when opened from
  /// [ProviderProfileScreen] (viewer is always a prospective customer
  /// there), or the customer's name/avatar when opened from
  /// [ProviderChatListScreen] by the provider themselves replying to a
  /// customer. Computed by the caller, not here — this screen has no way
  /// to know the viewer's role before the conversation itself loads.
  final String peerName;
  final String? peerAvatarUrl;
  final int? listingId;
  final String? listingName;
  final int? listingPrice;

  /// Set only by [ProviderChatListScreen] — that screen already knows
  /// which conversation row was tapped, so this screen fetches it directly
  /// (`GET /api/provider-chat/:id`, works for either side) instead of going
  /// through the customer-only `POST .../start` find-or-create flow (see
  /// [ProviderChatKey]'s own doc comment on why that flow 400s for a
  /// provider reopening their own inbox item).
  final int? conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final authState = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: 32,
                height: 32,
                child: peerAvatarUrl == null || peerAvatarUrl!.isEmpty
                    ? CircleAvatar(
                        radius: 16,
                        backgroundColor: context.mereytoiColors.goldPrimary
                            .withValues(alpha: 0.16),
                        child: Icon(
                          Icons.storefront_outlined,
                          size: 17,
                          color: context.mereytoiColors.goldPrimary,
                        ),
                      )
                    : NetworkImageBox(
                        url: ApiConfig.mediaUrl(peerAvatarUrl),
                        borderRadius: 0,
                      ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                peerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: switch (authState) {
        AuthInitial() || AuthLoading() => const AppLoader(),
        AuthUnauthenticated() => _LoginPrompt(locale: locale),
        AuthAuthenticated() => _ChatBody(
          providerId: providerId,
          listingId: listingId,
          listingName: listingName,
          listingPrice: listingPrice,
          conversationId: conversationId,
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
                ru: 'Войдите, чтобы написать услугодателю',
                kz: 'Қызмет көрсетушіге жазу үшін кіріңіз',
                en: 'Sign in to message the provider',
              ),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
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

class _ChatBody extends ConsumerStatefulWidget {
  const _ChatBody({
    required this.providerId,
    required this.listingId,
    required this.listingName,
    required this.listingPrice,
    required this.conversationId,
    required this.locale,
  });

  final int providerId;
  final int? listingId;
  final String? listingName;
  final int? listingPrice;
  final int? conversationId;
  final AppLocale locale;

  @override
  ConsumerState<_ChatBody> createState() => _ChatBodyState();
}

class _ChatBodyState extends ConsumerState<_ChatBody> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;
  String? _sendError;

  ProviderChatKey get _key => (
    providerId: widget.providerId,
    listingId: widget.listingId,
    conversationId: widget.conversationId,
  );

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom({required bool animate}) {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    if (animate) {
      _scrollController.animateTo(
        max,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(max);
    }
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
      await ref.read(providerChatProvider(_key).notifier).sendMessage(body);
    } catch (err) {
      // Retry on network error (brief section 5): the failed text is put
      // back into the field rather than lost, same as ManagerChatScreen's
      // own `_send` — the user can just tap send again.
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
    final chatAsync = ref.watch(providerChatProvider(_key));

    ref.listen(providerChatProvider(_key), (previous, next) {
      final prevLen = previous?.valueOrNull?.messages.length ?? 0;
      final nextLen = next.valueOrNull?.messages.length ?? 0;
      if (nextLen > prevLen) {
        final isFirstLoad = previous == null || previous.valueOrNull == null;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollToBottom(animate: !isFirstLoad),
        );
      }
    });

    return chatAsync.when(
      loading: () => const AppLoader(),
      error: (err, _) => Center(
        child: AppErrorView(
          message: apiErrorMessage(locale, err),
          locale: locale,
          onRetry: () => ref.read(providerChatProvider(_key).notifier).refresh(),
        ),
      ),
      data: (data) {
        final messages = data.messages;
        return Column(
          children: [
            _ContextCard(
              listingName: widget.listingName,
              listingPrice: widget.listingPrice,
              conversation: data.conversation,
              locale: locale,
            ),
            Expanded(
              child: messages.isEmpty
                  ? _EmptyState(locale: locale)
                  : ListView.builder(
                      controller: _scrollController,
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
            // SafeArea (not resizeToAvoidBottomInset tricks) keeps this bar
            // above both the OS nav bar and the keyboard — same
            // keyboard-safe pattern ManagerChatScreen already uses.
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
                            en: 'Write a message…',
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
    required this.listingName,
    required this.listingPrice,
    required this.conversation,
    required this.locale,
  });

  final String? listingName;
  final int? listingPrice;
  final ProviderConversation? conversation;
  final AppLocale locale;

  @override
  Widget build(BuildContext context) {
    final name = conversation?.listingName ?? listingName;
    final price = conversation?.listingPrice ?? listingPrice;
    if (name == null || name.isEmpty) return const SizedBox.shrink();

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
      child: Text(
        price != null && price > 0 ? '$name · ${formatPrice(price)}' : name,
        style: Theme.of(context).textTheme.bodyMedium,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.locale});

  final AppLocale locale;

  @override
  Widget build(BuildContext context) {
    // Same LayoutBuilder+SingleChildScrollView shape ManagerChatScreen's
    // own _EmptySuggestions uses — keeps this centered normally but
    // scrollable (never overflowing) once the keyboard shrinks the
    // available height.
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - AppSpacing.lg - AppSpacing.lg,
            ),
            child: Center(
              child: Text(
                t(
                  locale,
                  ru: 'Напишите первое сообщение услугодателю.',
                  kz: 'Қызмет көрсетушіге бірінші хабарлама жазыңыз.',
                  en: 'Send the provider your first message.',
                ),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MessageBubble extends ConsumerWidget {
  const _MessageBubble({required this.message});

  final ProviderMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final myUserId = authState is AuthAuthenticated ? authState.user.id : null;
    final isMine = myUserId != null && message.senderUserId == myUserId;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
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
          color: isMine
              ? context.mereytoiColors.goldPrimary.withValues(alpha: 0.16)
              : context.mereytoiColors.surface,
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
