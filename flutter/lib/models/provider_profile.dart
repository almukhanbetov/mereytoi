/// Mirrors backend/internal/models/provider.go's JSON shape — a user's
/// optional "услугодатель" profile (Этап 11). See ProviderService's own
/// doc comment for the /api/provider/* endpoints this is parsed from.
class ProviderProfile {
  const ProviderProfile({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.city,
    required this.description,
    required this.phone,
    required this.whatsapp,
    required this.telegram,
    required this.avatarUrl,
    required this.status,
  });

  final int id;
  final int userId;
  final String displayName;
  final String city;
  final String description;
  final String phone;
  final String whatsapp;
  final String telegram;
  final String avatarUrl;
  final String status;

  factory ProviderProfile.fromJson(Map<String, dynamic> json) {
    return ProviderProfile(
      id: json['id'] as int,
      userId: json['user_id'] as int? ?? 0,
      displayName: json['display_name'] as String? ?? '',
      city: json['city'] as String? ?? '',
      description: json['description'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      whatsapp: json['whatsapp'] as String? ?? '',
      telegram: json['telegram'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String? ?? '',
      status: json['status'] as String? ?? '',
    );
  }
}
