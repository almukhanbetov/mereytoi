/// Mirrors backend/internal/models/manager_chat.go's `ManagerMessage` — one
/// line in a `ManagerConversation`.
class ManagerMessage {
  const ManagerMessage({
    required this.id,
    required this.conversationId,
    required this.senderType,
    this.senderUserId,
    required this.body,
    this.readAt,
    required this.createdAt,
  });

  final int id;
  final int conversationId;

  /// "user" | "manager" — which side sent this, independent of exactly
  /// which admin account replied.
  final String senderType;
  final int? senderUserId;
  final String body;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get isFromManager => senderType == 'manager';

  factory ManagerMessage.fromJson(Map<String, dynamic> json) {
    return ManagerMessage(
      id: json['id'] as int,
      conversationId: json['conversation_id'] as int? ?? 0,
      senderType: json['sender_type'] as String? ?? 'user',
      senderUserId: json['sender_user_id'] as int?,
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
