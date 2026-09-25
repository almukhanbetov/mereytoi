import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/provider_conversation.dart';
import '../models/provider_message.dart';
import '../services/provider_chat_service.dart';
import 'providers.dart';

/// Which conversation a chat screen was opened for. Two distinct shapes,
/// unlike `ManagerChatKey`: `POST /api/provider-chat/start` (find-or-create
/// by providerId/listingId) is a *customer-only* flow — the backend's own
/// dedup query matches on `customer_user_id = caller`, so a provider
/// calling it to reopen their own inbox item would search for a
/// conversation where *they* are the customer (never true) and hit the
/// "cannot message your own provider profile" guard instead. A provider
/// opening a conversation from ProviderChatListScreen already knows its
/// [conversationId] and must fetch it directly via `GET
/// /api/provider-chat/:id` (works for either side — see
/// ProviderChatHandler.Get/conversationRole on the backend) rather than
/// going through `start`. [providerId]/[listingId] stay required for the
/// customer-side "peek or start" path (ProviderProfileScreen/
/// MessageProviderButton, which never know a conversationId yet).
typedef ProviderChatKey = ({
  int providerId,
  int? listingId,
  int? conversationId,
});

class ProviderChatState {
  const ProviderChatState({this.conversation, this.messages = const []});

  final ProviderConversation? conversation;
  final List<ProviderMessage> messages;

  ProviderChatState copyWith({
    ProviderConversation? conversation,
    List<ProviderMessage>? messages,
  }) {
    return ProviderChatState(
      conversation: conversation ?? this.conversation,
      messages: messages ?? this.messages,
    );
  }
}

/// Owns one conversation's lifecycle: open-or-peek on construction, poll for
/// the other side's replies every 5s while alive (same cadence
/// [ManagerChatNotifier] uses), send. Mirrors ManagerChatNotifier's shape
/// exactly — the two features are deliberately parallel, not shared, since
/// their backends are separate models (see ProviderChatService's own doc
/// comment).
class ProviderChatNotifier
    extends StateNotifier<AsyncValue<ProviderChatState>> {
  ProviderChatNotifier(this._ref, this._key)
    : super(const AsyncValue.loading()) {
    _load();
  }

  static const _pollInterval = Duration(seconds: 5);

  final Ref _ref;
  final ProviderChatKey _key;
  Timer? _pollTimer;

  ProviderChatService get _service => _ref.read(providerChatServiceProvider);

  Future<void> _load() async {
    state = const AsyncValue.loading();
    try {
      final knownId = _key.conversationId;
      final (conversation, messages) = knownId != null
          ? await _service.get(knownId)
          : await _service.start(
              providerId: _key.providerId,
              listingId: _key.listingId,
            );
      if (!mounted) return;
      state = AsyncValue.data(
        ProviderChatState(conversation: conversation, messages: messages),
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
        ProviderChatState(conversation: conversation, messages: messages),
      );
    } catch (_) {
      // A polling failure shouldn't disrupt an already-visible thread — the
      // next tick just tries again.
    }
  }

  Future<void> refresh() => _load();

  Future<void> sendMessage(String body) async {
    final conversationId = state.valueOrNull?.conversation?.id;
    final (conversation, messages) = conversationId != null
        ? await _service.addMessage(conversationId: conversationId, body: body)
        : await _service.start(
            providerId: _key.providerId,
            listingId: _key.listingId,
            message: body,
          );
    if (!mounted) return;
    state = AsyncValue.data(
      ProviderChatState(conversation: conversation, messages: messages),
    );
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

final providerChatProvider = StateNotifierProvider.autoDispose
    .family<ProviderChatNotifier, AsyncValue<ProviderChatState>, ProviderChatKey>((
      ref,
      key,
    ) {
      return ProviderChatNotifier(ref, key);
    });

/// `GET /api/provider-chat` — the dialogs-list screen's own data source.
/// `autoDispose` so leaving the list screen drops the poll-free one-shot
/// fetch; the list screen itself re-fetches (via pull-to-refresh/re-entry)
/// rather than polling continuously, since staleness here is much less
/// time-sensitive than an open conversation.
final providerConversationsProvider =
    FutureProvider.autoDispose<List<ProviderConversationSummary>>((ref) async {
      return ref.read(providerChatServiceProvider).list();
    });
