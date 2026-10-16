import '../core/network/api_client.dart';
import '../models/city.dart';

/// Wraps GET /api/cities — the backend's fixed city directory, whose IDs
/// GET /api/listings' `city_id` filter accepts.
class CityService {
  CityService(this._client);

  final ApiClient _client;

  Future<List<City>> fetchCities() async {
    final json = await _client.getJson('/api/cities');
    final raw = json['cities'] as List? ?? const [];
    return raw
        .map((e) => City.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}
