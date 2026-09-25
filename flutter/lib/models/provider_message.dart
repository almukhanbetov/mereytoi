/// Mirrors backend/internal/models/provider_chat.go's `ProviderMessage` —
/// one line in a `ProviderConversation`. No senderType (unlike
/// ManagerMessage): a provider-chat conversation only ever has two possible
/// senders (the customer or the provider's own account), so a screen
/// decides "is this my own message" by comparing [senderUserId] against
/// the app's own logged-in user id, not a separate tag.
class ProviderMessage {
  const ProviderMessage({
    required this.id,
    required this.conversationId,
    required this.senderUserId,
    required this.body,
    this.readAt,
    required this.createdAt,
  });

  final int id;
  final int conversationId;
  final int senderUserId;
  final String body;
  final DateTime? readAt;
  final DateTime createdAt;

  factory ProviderMessage.fromJson(Map<String, dynamic> json) {
    return ProviderMessage(
      id: json['id'] as int,
      conversationId: json['conversation_id'] as int? ?? 0,
      senderUserId: json['sender_user_id'] as int? ?? 0,
      body: json['body'] as String? ?? '',
      readAt: json['read_at'] != null
          ? DateTime.tryParse(json['read_at'] as String)
          : null,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
