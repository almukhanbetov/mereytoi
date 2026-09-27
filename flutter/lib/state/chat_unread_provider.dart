import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';
import 'manager_chat_provider.dart';
import 'provider_chat_provider.dart';

/// Total unread chat messages for the global chat button's badge: the
/// manager's unread replies plus unread provider-chat messages, straight
/// from the two existing list endpoints' own `unread_count`s. Always 0 for
/// a guest — never calls an auth-only endpoint just to get a 401. A
/// failing list simply contributes 0 (a badge is not worth an error).
final chatUnreadCountProvider = Provider.autoDispose<int>((ref) {
  if (ref.watch(authProvider) is! AuthAuthenticated) return 0;
  final manager =
      ref.watch(managerConversationsProvider).valueOrNull ?? const [];
  final provider =
      ref.watch(providerConversationsProvider).valueOrNull ?? const [];
  return manager.fold<int>(0, (sum, s) => sum + s.unreadCount) +
      provider.fold<int>(0, (sum, s) => sum + s.unreadCount);
});

/// Re-fetches both conversation lists — called whenever the user comes
/// back from the "Сообщения" hub or a chat, so the badge/list reflect the
/// messages that were just read.
void refreshChatLists(WidgetRef ref) {
  ref.invalidate(managerConversationsProvider);
  ref.invalidate(providerConversationsProvider);
}
