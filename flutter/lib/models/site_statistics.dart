/// Mirrors the JSON returned by GET /api/site-statistics
/// (backend/internal/handlers/site_statistics_handler.go's statsJSON()) —
/// plain integers; the "+" suffix and locale grouping ("15 000+") are
/// display-only, added in the widget, never stored/parsed here.
class SiteStatistics {
  const SiteStatistics({
    required this.eventsCount,
    required this.happyGuestsCount,
    required this.yearsExperience,
    required this.citiesCount,
  });

  final int eventsCount;
  final int happyGuestsCount;
  final int yearsExperience;
  final int citiesCount;

  factory SiteStatistics.fromJson(Map<String, dynamic> json) {
    return SiteStatistics(
      eventsCount: json['events_count'] as int? ?? 0,
      happyGuestsCount: json['happy_guests_count'] as int? ?? 0,
      yearsExperience: json['years_experience'] as int? ?? 0,
      citiesCount: json['cities_count'] as int? ?? 0,
    );
  }
}
