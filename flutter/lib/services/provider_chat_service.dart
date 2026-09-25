import '../core/network/api_client.dart';
import '../models/provider_conversation.dart';
import '../models/provider_message.dart';

/// Wraps `/api/provider-chat/*` — Этап 11G's "Написать услугодателю",
/// deliberately separate from [ManagerChatService] (see
/// backend/internal/models/provider_chat.go's own doc comment). Every
/// method here requires an authenticated caller (`RequireAuth` on the
/// backend); callers check auth state first, same convention
/// [ManagerChatService] already established.
class ProviderChatService {
  ProviderChatService(this._client);

  final ApiClient _client;

  /// `POST /api/provider-chat/start` — finds-or-creates the one
  /// conversation for (this customer, providerId, listingId) and, if
  /// `message` is non-empty, posts it. An empty `message` just "peeks" —
  /// `conversation` in the response can be null if nothing exists yet for
  /// this exact (provider, listing) pair.
  Future<(ProviderConversation?, List<ProviderMessage>)> start({
    required int providerId,
    int? listingId,
    String message = '',
  }) async {
    final json = await _client.postJson('/api/provider-chat/start', {
      'provider_id': providerId,
      'listing_id': listingId,
      'message': message,
    });
    return _parseDetail(json);
  }

  /// `GET /api/provider-chat` — every conversation the caller is a
  /// participant of, either as a customer or (if they have a provider
  /// profile) as that provider, newest-activity first.
  Future<List<ProviderConversationSummary>> list() async {
    final json = await _client.getJson('/api/provider-chat');
    final raw = json['conversations'] as List? ?? const [];
    return raw
        .map(
          (e) => ProviderConversationSummary.fromJson(
            Map<String, dynamic>.from(e as Map),
          ),
        )
        .toList();
  }

  /// `GET /api/provider-chat/:id` — also marks the other side's unseen
  /// messages read as a side effect (no separate mark-read endpoint).
  Future<(ProviderConversation?, List<ProviderMessage>)> get(
    int conversationId,
  ) async {
    final json = await _client.getJson('/api/provider-chat/$conversationId');
    return _parseDetail(json);
  }

  Future<(ProviderConversation?, List<ProviderMessage>)> addMessage({
    required int conversationId,
    required String body,
  }) async {
    final json = await _client.postJson(
      '/api/provider-chat/$conversationId/messages',
      {'body': body},
    );
    return _parseDetail(json);
  }

  (ProviderConversation?, List<ProviderMessage>) _parseDetail(
    Map<String, dynamic> json,
  ) {
    final conversation = json['conversation'] is Map
        ? ProviderConversation.fromJson(
            Map<String, dynamic>.from(json['conversation'] as Map),
          )
        : null;
    final rawMessages = json['messages'] as List? ?? const [];
    final messages = rawMessages
        .map(
          (e) =>
              ProviderMessage.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
    return (conversation, messages);
  }
}
