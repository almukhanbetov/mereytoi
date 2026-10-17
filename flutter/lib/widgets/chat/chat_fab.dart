import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../screens/messages/messages_screen.dart';
import '../../state/chat_unread_provider.dart';
import '../../state/locale_provider.dart';

/// The chat button's diameter.
const kChatFabSize = 52.0;

/// Fill opacity of the chat button.
const kChatFabOpacity = 0.68;

/// Gap between the bottom navigation's top edge and the chat button — far
/// enough that the button never touches the nav (≈82 above the screen
/// bottom with a 54 nav bar; the nav's own safe-area inset lifts it too).
const kChatFabNavGap = 28.0;

/// Bottom padding every main-tab scroll view ends with, so its last item
/// can scroll fully above the floating chat button: the gap, the button
/// and a little air.
const kChatFabClearance = kChatFabNavGap + kChatFabSize + AppSpacing.md;

/// Where [RootShell] floats [ChatFab]: Material's end-float position (16
/// from the right, snack bars and safe area respected), raised so the
/// button sits [kChatFabNavGap] above the nav instead of the default 16.
const FloatingActionButtonLocation kChatFabLocation = _ChatFabLocation();

class _ChatFabLocation extends StandardFabLocation
    with FabEndOffsetX, FabFloatOffsetY {
  const _ChatFabLocation();

  @override
  double getOffsetY(
    ScaffoldPrelayoutGeometry scaffoldGeometry,
    double adjustment,
  ) =>
      super.getOffsetY(scaffoldGeometry, adjustment) -
      (kChatFabNavGap - kFloatingActionButtonMargin);
}

/// How long the chat button takes to slide/fade out and back in.
const kChatFabAnimationDuration = Duration(milliseconds: 200);

/// How long after scrolling stops the chat button comes back.
const kChatFabReshowDelay = Duration(milliseconds: 600);

/// A tab counts as "at the top" up to this scroll offset.
const kChatFabTopThreshold = 2.0;

/// Whether the floating chat button is currently shown, driven by each
/// main tab's own vertical scrolling: hidden while content scrolls down (so
/// it never sits on the cards passing underneath), shown again on
/// scrolling up or [kChatFabReshowDelay] after scrolling stops.
/// Horizontal and nested scrollables (Home's carousels) are ignored.
///
/// Tabs in [hiddenAtTopTabs] also keep the button hidden while they're at
/// the very top (offset ≤ [kChatFabTopThreshold]) — for a tab whose first
/// card would otherwise sit right under the button. Every other tab shows
/// it at the top, as the chat's main entry point.
class ChatFabVisibility extends ChangeNotifier {
  ChatFabVisibility({this.hiddenAtTopTabs = const {}, int initialTab = 0})
    : _tab = initialTab {
    _visible = _canShow(initialTab);
  }

  final Set<int> hiddenAtTopTabs;
  int _tab;
  late bool _visible;
  final _offsets = <int, double>{};
  Timer? _reshow;

  bool get visible => _visible;

  bool _atTop(int tab) => (_offsets[tab] ?? 0) <= kChatFabTopThreshold;

  bool _canShow(int tab) => !(hiddenAtTopTabs.contains(tab) && _atTop(tab));

  /// The active tab changed: show the button unless that tab keeps it
  /// hidden at its current (remembered) position.
  void selectTab(int tab) {
    _tab = tab;
    _setVisible(_canShow(tab));
  }

  /// Feed every [ScrollNotification] from tab [tab]'s body here. Never
  /// consumes the notification.
  bool handleScroll(int tab, ScrollNotification notification) {
    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical || notification.depth != 0) {
      return false;
    }
    _offsets[tab] = metrics.pixels;
    if (tab != _tab) return false;
    switch (notification) {
      case UserScrollNotification(:final direction):
        switch (direction) {
          case ScrollDirection.reverse:
            _setVisible(false);
          case ScrollDirection.forward:
            _setVisible(_canShow(tab));
          case ScrollDirection.idle:
            _scheduleShow();
        }
      case ScrollEndNotification():
        _scheduleShow();
      case ScrollUpdateNotification() when _atTop(tab):
        _setVisible(_canShow(tab));
      default:
        break;
    }
    return false;
  }

  void _scheduleShow() {
    if (!_canShow(_tab)) {
      _setVisible(false);
      return;
    }
    if (_visible) return;
    _reshow?.cancel();
    _reshow = Timer(kChatFabReshowDelay, () => _setVisible(_canShow(_tab)));
  }

  void _setVisible(bool value) {
    _reshow?.cancel();
    if (_visible == value) return;
    _visible = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _reshow?.cancel();
    super.dispose();
  }
}

/// [ChatFab] that slides down and fades out while [visibility] says so —
/// it stays in the layout (no jump), and ignores taps while hidden.
class AutoHideChatFab extends StatelessWidget {
  const AutoHideChatFab({super.key, required this.visibility});

  final ChatFabVisibility visibility;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: visibility,
      builder: (context, child) {
        final visible = visibility.visible;
        return IgnorePointer(
          ignoring: !visible,
          child: AnimatedSlide(
            offset: visible ? Offset.zero : const Offset(0, 0.6),
            duration: kChatFabAnimationDuration,
            curve: Curves.easeOut,
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: kChatFabAnimationDuration,
              curve: Curves.easeOut,
              child: child,
            ),
          ),
        );
      },
      child: const ChatFab(),
    );
  }
}

/// The global chat entry point — a compact, slightly translucent gold
/// round button the root shell floats above the bottom navigation on its
/// main tabs. Its badge
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
            // Small and soft: under a translucent fill a heavy shadow
            // would read as a dark disc.
            boxShadow: [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Material(
            // Translucent so whatever scrolls behind it stays faintly
            // visible instead of being blotted out.
            color: colors.goldPrimary.withValues(alpha: kChatFabOpacity),
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
                width: kChatFabSize,
                height: kChatFabSize,
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
                      size: 22,
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
