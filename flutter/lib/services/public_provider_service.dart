import '../core/network/api_client.dart';
import '../models/provider_public_profile.dart';

/// Wraps `GET /api/providers/:id` — Этап 11G's public "профиль
/// услугодателя", no auth required. Deliberately its own service (not a
/// method on [ProviderService], which is entirely `/api/provider/*` — the
/// caller's own profile, auth-only).
class PublicProviderService {
  PublicProviderService(this._client);

  final ApiClient _client;

  Future<ProviderPublicProfile> get(int providerId) async {
    final json = await _client.getJson('/api/providers/$providerId');
    return ProviderPublicProfile.fromJson(json);
  }
}
