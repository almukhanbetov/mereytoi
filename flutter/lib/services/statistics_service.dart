import '../core/network/api_client.dart';
import '../models/site_statistics.dart';

/// Wraps the public GET /api/site-statistics — the admin PUT counterpart is
/// intentionally never called from this app (admin already exists on web).
class StatisticsService {
  StatisticsService(this._client);

  final ApiClient _client;

  Future<SiteStatistics> fetchStatistics() async {
    final json = await _client.getJson('/api/site-statistics');
    return SiteStatistics.fromJson(json);
  }
}
