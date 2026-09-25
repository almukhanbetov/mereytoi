import 'listing.dart';

/// `GET /api/providers/:id` (public, no auth) — mirrors backend's
/// `providerDetailOut` + the listings/count wrapper from
/// PublicProviderHandler.Get. Deliberately its own model, not
/// `ProviderProfile` (that one mirrors `/api/provider/me`'s owner-only
/// shape, which includes `user_id`/`status` — internal fields this public
/// shape never has, Этап 11G brief: "не показывать внутренние
/// user_id/provider_id").
class ProviderPublicProfile {
  const ProviderPublicProfile({
    required this.id,
    required this.displayName,
    required this.city,
    required this.description,
    required this.avatarUrl,
    required this.phone,
    required this.whatsapp,
    required this.telegram,
    required this.listings,
    required this.listingCount,
  });

  final int id;
  final String displayName;
  final String city;
  final String description;
  final String avatarUrl;
  final String phone;
  final String whatsapp;
  final String telegram;
  final List<Listing> listings;
  final int listingCount;

  factory ProviderPublicProfile.fromJson(Map<String, dynamic> json) {
    final provider = Map<String, dynamic>.from(json['provider'] as Map);
    final rawListings = json['listings'] as List? ?? const [];
    return ProviderPublicProfile(
      id: provider['id'] as int,
      displayName: provider['display_name'] as String? ?? '',
      city: provider['city'] as String? ?? '',
      description: provider['description'] as String? ?? '',
      avatarUrl: provider['avatar_url'] as String? ?? '',
      phone: provider['phone'] as String? ?? '',
      whatsapp: provider['whatsapp'] as String? ?? '',
      telegram: provider['telegram'] as String? ?? '',
      listings: rawListings
          .map((e) => Listing.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      listingCount: json['listing_count'] as int? ?? 0,
    );
  }
}
