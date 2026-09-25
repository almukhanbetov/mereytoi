import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/api_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../models/provider_conversation.dart';
import '../../state/auth_provider.dart';
import '../../state/locale_provider.dart';
import '../../state/provider_chat_provider.dart';
import '../../widgets/app_error_view.dart';
import '../../widgets/app_icon_badge.dart';
import '../../widgets/app_loader.dart';
import '../../widgets/network_image_box.dart';
import 'provider_chat_screen.dart';

/// The dialogs-list screen (Этап 11G brief section 5/6) — every
/// provider-chat conversation the caller is a participant of, on either
/// side (GET /api/provider-chat already merges both roles). Reached two
/// ways: "Сообщения от клиентов" under the provider's own profile section
/// (brief section 6), and a generic "Мои переписки" entry under Profile ->
/// Support that any customer can reach too — both push this exact same
/// screen, no separate customer/provider variant.
class ProviderChatListScreen extends ConsumerWidget {
  const ProviderChatListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final authState = ref.watch(authProvider);
    final myUserId = authState is AuthAuthenticated ? authState.user.id : null;
    final conversationsAsync = ref.watch(providerConversationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          t(locale, ru: 'Диалоги', kz: 'Диалогтар', en: 'Conversations'),
        ),
      ),
      body: conversationsAsync.when(
        loading: () => const AppLoader(),
        error: (err, _) => Center(
          child: AppErrorView(
            message: apiErrorMessage(locale, err),
            locale: locale,
            onRetry: () => ref.invalidate(providerConversationsProvider),
          ),
        ),
        data: (summaries) {
          if (summaries.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppIconBadge(icon: Icons.chat_bubble_outline_rounded),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      t(
                        locale,
                        ru: 'Пока нет диалогов',
                        kz: 'Әзірге диалог жоқ',
                        en: 'No conversations yet',
                      ),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            color: context.mereytoiColors.goldPrimary,
            backgroundColor: context.mereytoiColors.surfaceElevated,
            onRefresh: () => ref.refresh(providerConversationsProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: summaries.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
              itemBuilder: (context, i) => _ConversationRow(
                summary: summaries[i],
                myUserId: myUserId,
                locale: locale,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({
    required this.summary,
    required this.myUserId,
    required this.locale,
  });

  final ProviderConversationSummary summary;
  final int? myUserId;
  final AppLocale locale;

  @override
  Widget build(BuildContext context) {
    final conv = summary.conversation;
    // Which side am I? Determines whose name/avatar to show as "who this
    // conversation is with" (never my own).
    final iAmCustomer = conv.customerUserId == myUserId;
    final peer = iAmCustomer ? conv.provider : conv.customer;
    final peerName = peer?.displayName ?? '—';
    final peerAvatarUrl = iAmCustomer ? peer?.avatarUrl : null;

    return Material(
      color: context.mereytoiColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProviderChatScreen(
              providerId: conv.providerId,
              peerName: peerName,
              peerAvatarUrl: peerAvatarUrl,
              listingId: conv.listingId,
              listingName: conv.listingName,
              listingPrice: conv.listingPrice,
              conversationId: conv.id,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: peerAvatarUrl == null || peerAvatarUrl.isEmpty
                      ? const AppIconBadge(
                          icon: Icons.storefront_outlined,
                          size: 44,
                        )
                      : NetworkImageBox(
                          url: ApiConfig.mediaUrl(peerAvatarUrl),
                          borderRadius: 0,
                        ),
                ),
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
                            peerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        if (summary.lastMessageAt != null)
                          Text(
                            _timeLabel(summary.lastMessageAt!),
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: context.mereytoiColors.textMuted,
                                ),
                          ),
                      ],
                    ),
                    if (conv.listingName != null &&
                        conv.listingName!.isNotEmpty)
                      Text(
                        conv.listingName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: context.mereytoiColors.goldMuted,
                        ),
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
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: context.mereytoiColors.goldPrimary,
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                  ),
                  child: Text(
                    '${summary.unreadCount}',
                    style: TextStyle(
                      color: context.mereytoiColors.onGold,
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

  String _timeLabel(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
