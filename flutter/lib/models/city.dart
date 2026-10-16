import '../state/locale_provider.dart';

/// Mirrors backend/internal/cities/cities.go's JSON shape exactly —
/// GET /api/cities. The backend directory is the single source of truth;
/// its IDs are stable (append-only), which is what lets the app persist
/// just the ID.
class City {
  const City({
    required this.id,
    required this.nameRu,
    required this.nameKz,
    required this.nameEn,
  });

  final int id;
  final String nameRu;
  final String nameKz;
  final String nameEn;

  factory City.fromJson(Map<String, dynamic> json) {
    return City(
      id: json['id'] as int,
      nameRu: json['name_ru'] as String? ?? '',
      nameKz: json['name_kz'] as String? ?? '',
      nameEn: json['name_en'] as String? ?? '',
    );
  }

  String name(AppLocale locale) =>
      t(locale, ru: nameRu, kz: nameKz, en: nameEn);

  /// Local search for the city picker — case-insensitive substring match
  /// against all three names regardless of the active language, so "алм",
  /// "Almaty" and "қарағ" all work from any locale. Hyphens count as
  /// spaces, the same normalization the backend applies to city text.
  bool matches(String query) {
    final q = _normalize(query);
    if (q.isEmpty) return true;
    return _normalize(nameRu).contains(q) ||
        _normalize(nameKz).contains(q) ||
        _normalize(nameEn).contains(q);
  }

  static String _normalize(String s) => s
      .toLowerCase()
      .replaceAll('-', ' ')
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .join(' ');
}
