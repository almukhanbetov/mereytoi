import '../core/network/api_client.dart';
import '../models/listing.dart';
import '../models/provider_profile.dart';

/// "Стать услугодателем" / "Мои услуги" — Этап 11. Every
/// `/api/provider/*` endpoint this app uses; confirmed directly against
/// backend/internal/handlers/provider_handler.go and listing_handler.go's
/// CreateOwn before writing this (no endpoint here is invented). Listing
/// update/delete for a provider's own service reuse
/// [ListingManagementService.updateListing]/`deleteListing` — the exact
/// same PUT/DELETE /api/listings/:id an admin uses, now also authorized
/// for an owner/manager via `RequireListingAccess` — not duplicated here.
class ProviderService {
  ProviderService(this._client);

  final ApiClient _client;

  /// GET /api/provider/me — throws an [ApiException] with
  /// `ApiErrorType.notFound` when the caller has no profile yet; callers
  /// (see providerProfileProvider) treat that specific case as "not a
  /// provider", not an error state.
  Future<ProviderProfile> me() async {
    final json = await _client.getJson('/api/provider/me');
    return ProviderProfile.fromJson(
      Map<String, dynamic>.from(json['provider'] as Map),
    );
  }

  Future<ProviderProfile> create({
    required String displayName,
    String city = '',
    String description = '',
    String phone = '',
    String whatsapp = '',
    String telegram = '',
    String avatarUrl = '',
  }) async {
    final json = await _client.postJson('/api/provider', {
      'display_name': displayName,
      'city': city,
      'description': description,
      'phone': phone,
      'whatsapp': whatsapp,
      'telegram': telegram,
      'avatar_url': avatarUrl,
    });
    return ProviderProfile.fromJson(
      Map<String, dynamic>.from(json['provider'] as Map),
    );
  }

  Future<ProviderProfile> update({
    required String displayName,
    String city = '',
    String description = '',
    String phone = '',
    String whatsapp = '',
    String telegram = '',
    String avatarUrl = '',
  }) async {
    final json = await _client.putJson('/api/provider/me', {
      'display_name': displayName,
      'city': city,
      'description': description,
      'phone': phone,
      'whatsapp': whatsapp,
      'telegram': telegram,
      'avatar_url': avatarUrl,
    });
    return ProviderProfile.fromJson(
      Map<String, dynamic>.from(json['provider'] as Map),
    );
  }

  /// POST /api/provider/me/listings — the one genuinely new self-serve
  /// write endpoint this stage adds (see CreateOwn's own doc comment on
  /// the backend): requires an existing provider profile, and creates the
  /// matching `ListingManager(role=owner)` row server-side in the same
  /// transaction. "Мои услуги" itself reads back via the pre-existing
  /// `GET /api/users/me/listings` ([ListingService.fetchMyListings]) — no
  /// separate list endpoint here.
  Future<Listing> createListing({
    required int categoryId,
    required String nameRu,
    required String nameKz,
    String descriptionRu = '',
    String descriptionKz = '',
    String city = '',
    int price = 0,
    String priceType = 'fixed',
    List<String> imageUrls = const [],
  }) async {
    final json = await _client.postJson('/api/provider/me/listings', {
      'category_id': categoryId,
      'name_ru': nameRu,
      'name_kz': nameKz,
      'description_ru': descriptionRu,
      'description_kz': descriptionKz,
      'city': city,
      'price': price,
      'price_type': priceType,
      'image_urls': imageUrls,
    });
    return Listing.fromJson(Map<String, dynamic>.from(json['listing'] as Map));
  }
}
