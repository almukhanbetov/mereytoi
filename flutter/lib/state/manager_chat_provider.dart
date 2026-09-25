import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/manager_conversation.dart';
import '../models/manager_message.dart';
import '../services/manager_chat_service.dart';
import 'providers.dart';

/// Which context a chat was opened for — the only two fields the backend
/// actually keys a conversation on (`event_id`/`listing_id`); everything
/// else display-only (names/prices/hall/menu/guests) is passed straight
/// into `ManagerChatScreen` as widget params, not through this key, since
/// the backend has no columns for it anyway (see `ManagerChatContext`'s
/// own doc comment).
///
/// [conversationId] (Этап 12B) is set only when the caller already knows
/// the exact thread — a `manager_message_received` notification. Opening
/// by id fetches that conversation directly (`GET /api/manager-chat/:id`)
/// instead of re-resolving it by context through `start`, which would miss
/// a thread the manager has since closed (start only matches open ones).
typedef ManagerChatKey = ({int? eventId, int? listingId, int? conversationId});

class ManagerChatState {
  const ManagerChatState({this.conversation, this.messages = const []});

  final ManagerConversation? conversation;
  final List<ManagerMessage> messages;

  ManagerChatState copyWith({
    ManagerConversation? conversation,
    List<ManagerMessage>? messages,
  }) {
    return ManagerChatState(
      conversation: conversation ?? this.conversation,
      messages: messages ?? this.messages,
    );
  }
}

/// Owns one conversation's lifecycle: open-or-peek on construction, poll
/// for the manager's replies every 5s while alive (same cadence
/// `FloatingManagerWidget.jsx` uses — "not a live team discussion"), send.
class ManagerChatNotifier extends StateNotifier<AsyncValue<ManagerChatState>> {
  ManagerChatNotifier(this._ref, this._key)
    : super(const AsyncValue.loading()) {
    _load();
  }

  static const _pollInterval = Duration(seconds: 5);

  final Ref _ref;
  final ManagerChatKey _key;
  Timer? _pollTimer;

  ManagerChatService get _service => _ref.read(managerChatServiceProvider);

  Future<void> _load() async {
    state = const AsyncValue.loading();
    try {
      final knownId = _key.conversationId;
      final (conversation, messages) = knownId != null
          ? await _service.get(knownId)
          : await _service.start(
              eventId: _key.eventId,
              listingId: _key.listingId,
            );
      if (!mounted) return;
      state = AsyncValue.data(
        ManagerChatState(conversation: conversation, messages: messages),
      );
      _startPolling();
    } catch (error, stackTrace) {
      if (!mounted) return;
      state = AsyncValue.error(error, stackTrace);
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    final conversationId = state.valueOrNull?.conversation?.id;
    if (conversationId == null) return;
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll(conversationId));
  }

  Future<void> _poll(int conversationId) async {
    if (!mounted) return;
    try {
      final (conversation, messages) = await _service.get(conversationId);
      if (!mounted) return;
      state = AsyncValue.data(
        ManagerChatState(conversation: conversation, messages: messages),
      );
    } catch (_) {
      // A polling failure shouldn't disrupt an already-visible thread —
      // the next tick just tries again.
    }
  }

  Future<void> refresh() => _load();

  /// Sends [body]; if this is the very first message of a brand-new
  /// thread, [firstMessagePrefix] (the restaurant/event context line) is
  /// prepended — never on any later message, matching the web widget's
  /// own "only the first message gets the context prefix" rule.
  Future<void> sendMessage(
    String body, {
    String firstMessagePrefix = '',
  }) async {
    final conversationId = state.valueOrNull?.conversation?.id;
    final (conversation, messages) = conversationId != null
        ? await _service.addMessage(conversationId: conversationId, body: body)
        : await _service.start(
            message: '$firstMessagePrefix$body',
            eventId: _key.eventId,
            listingId: _key.listingId,
          );
    if (!mounted) return;
    state = AsyncValue.data(
      ManagerChatState(conversation: conversation, messages: messages),
    );
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

final managerChatProvider = StateNotifierProvider.autoDispose
    .family<ManagerChatNotifier, AsyncValue<ManagerChatState>, ManagerChatKey>((
      ref,
      key,
    ) {
      return ManagerChatNotifier(ref, key);
    });
