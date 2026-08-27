/// Single place the backend's base URL lives — mirrors
/// frontend/src/lib/api.js's `API_URL` / `NEXT_PUBLIC_API_URL` convention:
/// the Next.js site talks to the same Go API at this same origin (Nginx
/// proxies /api and /uploads to the backend container in production), so
/// the Flutter app and the website are guaranteed to hit the same backend
/// and the same PostgreSQL database.
///
/// Override at build/run time for local development against a backend
/// started via `docker compose up -d db && go run ./cmd/server`, e.g.:
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8090
/// (10.0.2.2 is how the Android emulator reaches the host machine's
/// localhost; use your machine's LAN IP for a physical device.)
class ApiConfig {
  ApiConfig._();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://mereytoi.kz',
  );

  /// Turns a backend-relative path like "/uploads/x.png" into an absolute
  /// URL — same behavior as frontend/src/lib/media.js's mediaUrl().
  static String mediaUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '$baseUrl$path';
  }
}
