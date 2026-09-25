/// The redacted, display-only "who" for a [ProviderConversation]'s
/// provider/customer side — mirrors backend/internal/handlers/
/// provider_chat_handler.go's `providerChatParty` (name + avatar only, no
/// user_id/email/phone).
class ProviderChatParty {
  const ProviderChatParty({required this.displayName, this.avatarUrl});

  final String displayName;
  final String? avatarUrl;

  factory ProviderChatParty.fromJson(Map<String, dynamic> json) {
    return ProviderChatParty(
      displayName: json['display_name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}

/// Mirrors backend/internal/models/provider_chat.go's `ProviderConversation`
/// — a direct thread between one customer and one marketplace provider,
/// optionally about one specific listing. Deliberately separate from
/// `ManagerConversation` (see the backend model's own doc comment): "Спросить
/// менеджера" and "Написать услугодателю" are two different channels.
class ProviderConversation {
  const ProviderConversation({
    required this.id,
    required this.providerId,
    this.provider,
    required this.customerUserId,
    this.customer,
    this.listingId,
    this.listingName,
    this.listingPrice,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int providerId;
  final ProviderChatParty? provider;
  final int customerUserId;
  final ProviderChatParty? customer;
  final int? listingId;

  /// The conversation's listing context — only name/price (RU name, same
  /// simplification `ManagerChatContext`'s own fallback display uses); the
  /// screen doesn't need the full `Listing` shape for a context line.
  final String? listingName;
  final int? listingPrice;

  final DateTime createdAt;
  final DateTime updatedAt;

  factory ProviderConversation.fromJson(Map<String, dynamic> json) {
    final listing = json['listing'] is Map
        ? Map<String, dynamic>.from(json['listing'] as Map)
        : null;
    return ProviderConversation(
      id: json['id'] as int,
      providerId: json['provider_id'] as int? ?? 0,
      provider: json['provider'] is Map
          ? ProviderChatParty.fromJson(
              Map<String, dynamic>.from(json['provider'] as Map),
            )
          : null,
      customerUserId: json['customer_user_id'] as int? ?? 0,
      customer: json['customer'] is Map
          ? ProviderChatParty.fromJson(
              Map<String, dynamic>.from(json['customer'] as Map),
            )
          : null,
      listingId: json['listing_id'] as int?,
      listingName: listing?['name_ru'] as String?,
      listingPrice: listing?['price'] as int?,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// One row of `GET /api/provider-chat` — the conversation plus a cheap
/// preview, mirrors backend's `summary` type in ProviderChatHandler.List.
class ProviderConversationSummary {
  const ProviderConversationSummary({
    required this.conversation,
    this.lastMessageBody,
    this.lastMessageAt,
    required this.unreadCount,
  });

  final ProviderConversation conversation;
  final String? lastMessageBody;
  final DateTime? lastMessageAt;
  final int unreadCount;

  factory ProviderConversationSummary.fromJson(Map<String, dynamic> json) {
    final last = json['last_message'] is Map
        ? Map<String, dynamic>.from(json['last_message'] as Map)
        : null;
    return ProviderConversationSummary(
      conversation: ProviderConversation.fromJson(json),
      lastMessageBody: last?['body'] as String?,
      lastMessageAt: last?['created_at'] != null
          ? DateTime.tryParse(last!['created_at'] as String)
          : null,
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
    );
  }
}
