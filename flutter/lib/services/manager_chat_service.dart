import '../core/network/api_client.dart';
import '../models/manager_conversation.dart';
import '../models/manager_message.dart';

/// Wraps the real `/api/manager-chat/*` endpoints — mirrors
/// frontend/src/lib/managerChatApi.js route-for-route. Authenticated-only
/// on the backend (`middleware.RequireAuth`); callers must check auth
/// state before calling (see AuthState) rather than relying on a
/// guaranteed 401.
class ManagerChatService {
  ManagerChatService(this._client);

  final ApiClient _client;

  /// `POST /api/manager-chat/start` — finds-or-creates the one open
  /// conversation for (this user, event_id, listing_id) and, if `message`
  /// is non-empty, posts it. Safe to call repeatedly with the same
  /// context: reopening the same service's chat continues one thread
  /// instead of spawning a new row per open. An empty `message` just
  /// "peeks" — `conversation` in the response can be `null` if nothing
  /// exists yet for this exact context.
  Future<(ManagerConversation?, List<ManagerMessage>)> start({
    String message = '',
    int? eventId,
    int? listingId,
  }) async {
    final json = await _client.postJson('/api/manager-chat/start', {
      'message': message,
      'event_id': eventId,
      'listing_id': listingId,
    });
    return _parseDetail(json);
  }

  /// `GET /api/manager-chat/:id` — also marks the other side's unseen
  /// messages read as a side effect (no separate mark-read endpoint for
  /// this feature).
  Future<(ManagerConversation?, List<ManagerMessage>)> get(
    int conversationId,
  ) async {
    final json = await _client.getJson('/api/manager-chat/$conversationId');
    return _parseDetail(json);
  }

  Future<(ManagerConversation?, List<ManagerMessage>)> addMessage({
    required int conversationId,
    required String body,
  }) async {
    final json = await _client.postJson(
      '/api/manager-chat/$conversationId/messages',
      {'body': body},
    );
    return _parseDetail(json);
  }

  (ManagerConversation?, List<ManagerMessage>) _parseDetail(
    Map<String, dynamic> json,
  ) {
    final conversation = json['conversation'] is Map
        ? ManagerConversation.fromJson(
            Map<String, dynamic>.from(json['conversation'] as Map),
          )
        : null;
    final rawMessages = json['messages'] as List? ?? const [];
    final messages = rawMessages
        .map(
          (e) => ManagerMessage.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
    return (conversation, messages);
  }
}
