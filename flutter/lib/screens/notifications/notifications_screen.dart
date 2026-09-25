import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../domain/manager_chat/manager_chat_context.dart';
import '../../domain/notification/notification_type.dart';
import '../../models/app_notification.dart';
import '../../state/auth_provider.dart';
import '../../state/locale_provider.dart';
import '../../state/notification_actions.dart';
import '../../state/notification_providers.dart';
import '../../widgets/app_error_view.dart';
import '../../widgets/app_loader.dart';
import '../../widgets/app_skeleton.dart';
import '../auth/login_screen.dart';
import '../events/event_workspace_screen.dart';
import '../manager_chat/manager_chat_screen.dart';
import '../provider_chat/provider_chat_screen.dart';

/// Брифа section 2 — the in-app notification center. Renders localized
/// copy from `type` at read time (never a stored title/text — same
/// reasoning as `EventActivity`), deep-links via `entity_type`/`event_id`
/// where the backend actually supplies them (see
/// `domain/notification/notification_type.dart`'s own doc comment on
/// which types do).
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final authState = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          t(locale, ru: 'Уведомления', kz: 'Хабарламалар', en: 'Notifications'),
        ),
        actions: authState is AuthAuthenticated
            ? [
                TextButton(
                  onPressed: () =>
                      ref.read(notificationActionsProvider).markAllRead(),
                  child: Text(
                    t(
                      locale,
                      ru: 'Прочитать все',
                      kz: 'Барлығын оқу',
                      en: 'Mark all as read',
                    ),
                  ),
                ),
              ]
            : null,
      ),
      body: switch (authState) {
        AuthInitial() || AuthLoading() => const AppLoader(),
        AuthUnauthenticated() => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t(
                    locale,
                    ru: 'Войдите, чтобы видеть уведомления',
                    kz: 'Хабарламаларды көру үшін кіріңіз',
                    en: 'Sign in to see notifications',
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.md),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  ),
                  child: Text(
                    t(locale, ru: 'Войти', kz: 'Кіру', en: 'Sign in'),
                  ),
                ),
              ],
            ),
          ),
        ),
        AuthAuthenticated() => const _NotificationsList(),
      },
    );
  }
}

class _NotificationsList extends ConsumerWidget {
  const _NotificationsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final notificationsAsync = ref.watch(notificationsProvider);

    return RefreshIndicator(
      color: context.mereytoiColors.goldPrimary,
      backgroundColor: context.mereytoiColors.surfaceElevated,
      onRefresh: () => ref.refresh(notificationsProvider.future),
      child: notificationsAsync.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: List.generate(
            5,
            (_) => const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.sm),
              child: AppSkeleton(height: 64, borderRadius: AppRadius.md),
            ),
          ),
        ),
        error: (err, _) => ListView(
          children: [
            SizedBox(
              height: 420,
              child: AppErrorView(
                message: apiErrorMessage(locale, err),
                locale: locale,
                onRetry: () => ref.invalidate(notificationsProvider),
              ),
            ),
          ],
        ),
        data: (data) {
          final notifications = data.$1;
          if (notifications.isEmpty) {
            return ListView(
              children: [
                SizedBox(
                  height: 420,
                  child: Center(
                    child: Text(
                      t(
                        locale,
                        ru: 'Пока нет уведомлений',
                        kz: 'Әлі хабарлама жоқ',
                        en: 'No notifications yet',
                      ),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            itemCount: notifications.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
            itemBuilder: (context, i) => _NotificationTile(
              notification: notifications[i],
              locale: locale,
            ),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.notification, required this.locale});

  final AppNotification notification;
  final AppLocale locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = resolveNotificationTarget(
      type: notification.type,
      entityType: notification.entityType,
      eventId: notification.eventId,
    );
    final chatTarget = resolveChatNotificationTarget(
      type: notification.type,
      entityType: notification.entityType,
      entityId: notification.entityId,
      payload: notification.payload,
      fallbackPeerName: notification.actor?.name,
    );

    return Material(
      color: notification.isRead
          ? context.mereytoiColors.surface
          : context.mereytoiColors.surfaceElevated,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () async {
          if (!notification.isRead) {
            await ref
                .read(notificationActionsProvider)
                .markRead(notification.id);
          }
          if (chatTarget != null && context.mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => _chatScreenFor(chatTarget)),
            );
          } else if (target != null && context.mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => EventWorkspaceScreen(
                  eventId: target.eventId,
                  initialTabIndex: target.tabIndex,
                ),
              ),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!notification.isRead)
                Padding(
                  padding: EdgeInsets.only(top: 6, right: AppSpacing.xs),
                  child: CircleAvatar(
                    radius: 3.5,
                    backgroundColor: context.mereytoiColors.goldPrimary,
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _notificationText(locale, notification),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: notification.isRead
                            ? FontWeight.w500
                            : FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _timeAgo(locale, notification.createdAt),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Этап 12B — the exact conversation a chat notification points at, opened
/// by id so it's the same thread regardless of which side the viewer is on.
Widget _chatScreenFor(ChatNotificationTarget target) {
  return switch (target) {
    ManagerChatNotificationTarget() => ManagerChatScreen(
      conversationId: target.conversationId,
      chatContext: ManagerChatContext(
        eventId: target.eventId,
        listingId: target.listingId,
      ),
    ),
    ProviderChatNotificationTarget() => ProviderChatScreen(
      providerId: target.providerId,
      peerName: target.peerName,
      listingId: target.listingId,
      conversationId: target.conversationId,
    ),
  };
}

/// A one-line preview of a chat message for the notification row — long
/// messages are clipped here rather than relying on the row to ellipsize,
/// since the row's text wraps.
String _messagePreview(AppNotification n) {
  final body = (n.payload['body'] as String? ?? '').trim().replaceAll(
    RegExp(r'\s+'),
    ' ',
  );
  if (body.isEmpty) return '';
  // Grapheme-safe clip, so an emoji at the cut point never gets split.
  final chars = body.characters;
  return chars.length > 80 ? ': «${chars.take(80)}…»' : ': «$body»';
}

/// Renders the same kind of localized line
/// `frontend/src/lib/eventHelpers.js`'s `activityLine` builds for the
/// activity feed — this app doesn't have that helper (Stage 4's Activity
/// tab wasn't part of the brief), so a compact, notification-appropriate
/// equivalent is built here instead, driven by the same `type`/`payload`
/// shape.
String _notificationText(AppLocale locale, AppNotification n) {
  final name = n.payload['name'] as String?;
  final title = n.payload['title'] as String?;
  switch (n.type) {
    case notifCandidateAdded:
      return t(
        locale,
        ru: 'Добавлена услуга «${name ?? ''}»',
        kz: '«${name ?? ''}» қызметі қосылды',
      );
    case notifVoteAdded:
    case notifVoteChanged:
      return t(
        locale,
        ru: 'Новый голос за «${name ?? ''}»',
        kz: '«${name ?? ''}» үшін жаңа дауыс',
      );
    case notifCommentAdded:
      return t(
        locale,
        ru: 'Новый комментарий',
        kz: 'Жаңа пікір',
        en: 'New comment',
      );
    case notifBudgetUpdated:
      return t(
        locale,
        ru: 'Бюджет мероприятия обновлён',
        kz: 'Іс-шара бюджеті жаңартылды',
        en: 'Event budget updated',
      );
    case notifTaskCreated:
      return t(
        locale,
        ru: 'Новая задача «${title ?? ''}»',
        kz: '«${title ?? ''}» жаңа тапсырмасы',
      );
    case notifTaskUpdated:
      return t(
        locale,
        ru: 'Задача «${title ?? ''}» изменена',
        kz: '«${title ?? ''}» тапсырмасы өзгертілді',
      );
    case notifTaskCompleted:
      return t(
        locale,
        ru: 'Задача «${title ?? ''}» выполнена',
        kz: '«${title ?? ''}» тапсырмасы орындалды',
      );
    case notifMemberJoined:
      return t(
        locale,
        ru: '${name ?? ''} присоединился(-ась) к мероприятию',
        kz: '${name ?? ''} іс-шараға қосылды',
      );
    case notifMemberRoleChanged:
      return t(
        locale,
        ru: 'Ваша роль изменена',
        kz: 'Рөліңіз өзгертілді',
        en: 'Your role has changed',
      );
    case notifInvitationAccepted:
      return t(
        locale,
        ru: '${name ?? ''} принял(-а) приглашение',
        kz: '${name ?? ''} шақыруды қабылдады',
      );
    case notifRequestSubmitted:
    case notifRequestResubmitted:
      return t(
        locale,
        ru: 'Заявка отправлена менеджеру',
        kz: 'Өтінім менеджерге жіберілді',
        en: 'Request sent to the manager',
      );
    case notifRequestInReview:
      return t(
        locale,
        ru: 'Заявка на рассмотрении',
        kz: 'Өтінім қаралуда',
        en: 'Request under review',
      );
    case notifRequestChangesRequested:
      return t(
        locale,
        ru: 'Менеджер запросил правки',
        kz: 'Менеджер түзету сұрады',
        en: 'The manager requested changes',
      );
    case notifRequestApproved:
      return t(
        locale,
        ru: 'Заявка подтверждена',
        kz: 'Өтінім расталды',
        en: 'Request confirmed',
      );
    case notifRequestRejected:
      return t(
        locale,
        ru: 'Заявка отклонена',
        kz: 'Өтінім қабылданбады',
        en: 'Request declined',
      );
    case notifRequestCancelled:
      return t(
        locale,
        ru: 'Заявка отменена',
        kz: 'Өтінім болдырылмады',
        en: 'Request canceled',
      );
    case notifWorkspaceCreated:
      return t(
        locale,
        ru: 'Ваше пространство «Мой той» готово',
        kz: '«Менің тойым» кеңістігіңіз дайын',
        en: 'Your "My Event" space is ready',
      );
    case notifManagerMessageReceived:
      return t(
            locale,
            ru: 'Новое сообщение от менеджера',
            kz: 'Менеджерден жаңа хабарлама',
            en: 'New message from the manager',
          ) +
          _messagePreview(n);
    case notifManagerChatUserMessage:
      return t(
            locale,
            ru: 'Новое сообщение клиента менеджеру',
            kz: 'Клиенттен менеджерге жаңа хабарлама',
            en: 'New customer message to the managers',
          ) +
          _messagePreview(n);
    case notifProviderMessageReceived:
      final sender =
          (n.payload['sender_name'] as String?) ?? n.actor?.name ?? '';
      return (sender.isEmpty
              ? t(
                  locale,
                  ru: 'Новое сообщение',
                  kz: 'Жаңа хабарлама',
                  en: 'New message',
                )
              : t(
                  locale,
                  ru: 'Новое сообщение от $sender',
                  kz: '$sender жаңа хабарлама жіберді',
                  en: 'New message from $sender',
                )) +
          _messagePreview(n);
    default:
      return n.type;
  }
}

String _timeAgo(AppLocale locale, DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) {
    return t(locale, ru: 'только что', kz: 'жаңа ғана', en: 'just now');
  }
  if (diff.inMinutes < 60) {
    return '${diff.inMinutes} ${t(locale, ru: "мин", kz: "мин", en: "min")}';
  }
  if (diff.inHours < 24) {
    return '${diff.inHours} ${t(locale, ru: "ч", kz: "сағ", en: "h")}';
  }
  if (diff.inDays < 7) {
    return '${diff.inDays} ${t(locale, ru: "дн", kz: "күн", en: "d")}';
  }
  return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
}
