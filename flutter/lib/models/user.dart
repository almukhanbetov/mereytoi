/// Mirrors backend/internal/models/user.go's JSON shape exactly, as
/// returned by `POST /api/auth/login`, `POST /api/auth/register` and
/// `GET /api/auth/me` (all three respond with `{"user": {...}, ...}`).
///
/// `PasswordHash`/`PhoneNormalized`/`TelegramChatID`/`PreferredDeliveryChannel`
/// on the Go struct are tagged `json:"-"` — never sent to any client — so
/// they have no field here either; nothing here was invented beyond what
/// the backend actually serializes.
///
/// `telegramLinked`/`preferredDeliveryChannel` are *not* on the Go `User`
/// struct itself — `AuthHandler.Me` adds them as sibling keys next to
/// `"user"` in that one response only (`{"user":..., "telegram_linked":...,
/// "preferred_delivery_channel":...}`). Login/Register never send them, so
/// they stay `null` on a `User` built from those two and are only ever
/// filled in via [copyWith] after a `GET /api/auth/me` call — see
/// `AuthService.fetchMe`.
class User {
  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.phoneVerifiedAt,
    this.telegramLinked,
    this.preferredDeliveryChannel,
  });

  final int id;
  final String name;
  final String email;
  final String phone;
  final String role;

  /// "active" | "pending" (models.UserStatusActive/UserStatusPending) —
  /// every account created by Register is "active"; "pending" only exists
  /// for the booking→account onboarding flow (Stage-later scope), kept as
  /// a plain string rather than an enum since the backend itself treats it
  /// as one and may add values this app doesn't need to react to.
  final String status;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Always `null` today — the backend field exists (forward-compatible
  /// schema for a not-yet-built OTP flow) but nothing currently sets it,
  /// see models.User's own doc comment.
  final DateTime? phoneVerifiedAt;

  /// Only ever non-null after `GET /api/auth/me` — see the class doc above.
  final bool? telegramLinked;
  final String? preferredDeliveryChannel;

  bool get isAdmin => role == 'admin';

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      role: json['role'] as String? ?? 'user',
      status: json['status'] as String? ?? 'active',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      phoneVerifiedAt: json['phone_verified_at'] != null
          ? DateTime.tryParse(json['phone_verified_at'] as String)
          : null,
    );
  }

  User copyWith({bool? telegramLinked, String? preferredDeliveryChannel}) {
    return User(
      id: id,
      name: name,
      email: email,
      phone: phone,
      role: role,
      status: status,
      createdAt: createdAt,
      updatedAt: updatedAt,
      phoneVerifiedAt: phoneVerifiedAt,
      telegramLinked: telegramLinked ?? this.telegramLinked,
      preferredDeliveryChannel:
          preferredDeliveryChannel ?? this.preferredDeliveryChannel,
    );
  }
}
