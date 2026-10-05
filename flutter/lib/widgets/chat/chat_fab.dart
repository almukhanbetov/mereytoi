import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../screens/messages/messages_screen.dart';
import '../../state/chat_unread_provider.dart';
import '../../state/locale_provider.dart';

/// Extra bottom padding a main-tab scroll view needs so its last item can
/// scroll clear of [ChatFab] (56 + the Scaffold's own 16 FAB margin, plus
/// a little air).
const kChatFabClearance = 80.0;

/// The global chat entry point — a compact gold round button the root
/// shell floats above the bottom navigation on its main tabs. Its badge
/// is the total unread count across manager + provider chats
/// ([chatUnreadCountProvider]); tapping opens [MessagesScreen]. Shown to
/// guests too (MessagesScreen explains they need to sign in).
class ChatFab extends ConsumerWidget {
  const ChatFab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final unread = ref.watch(chatUnreadCountProvider);
    final colors = context.mereytoiColors;
    final label = t(
      locale,
      ru: 'Сообщения',
      kz: 'Хабарламалар',
      en: 'Messages',
    );

    return Semantics(
      button: true,
      label: unread > 0 ? '$label: $unread' : label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: AppShadows.card,
          ),
          child: Material(
            color: colors.goldPrimary,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const ValueKey('chat-fab'),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MessagesScreen()),
                );
                // Messages may have been read in the hub/chats.
                refreshChatLists(ref);
              },
              child: SizedBox(
                width: 56,
                height: 56,
                child: Center(
                  child: Badge(
                    label: Text(unread > 99 ? '99+' : '$unread'),
                    isLabelVisible: unread > 0,
                    backgroundColor: colors.error,
                    textStyle: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                    offset: const Offset(8, -8),
                    child: Icon(
                      Icons.chat_bubble_rounded,
                      size: 24,
                      color: colors.onGold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
