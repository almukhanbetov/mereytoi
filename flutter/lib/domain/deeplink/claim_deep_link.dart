/// Pure parser for the one deep link this app currently handles:
/// `https://mereytoi.kz/claim/:token` (see `frontend/src/app/claim/[token]
/// /page.js` — the same path web itself already uses for the claim link
/// delivered over WhatsApp/Telegram). Kept separate from the OS-level
/// listener (`deep_link_listener.dart`) so the URI→token mapping is
/// unit-testable without any platform channel involved.
///
/// Returns `null` for anything that isn't recognizably a claim link —
/// wrong host, wrong path shape, or a missing/empty token — so the
/// listener can silently ignore a link it doesn't understand rather than
/// guessing at one.
String? parseClaimToken(Uri uri) {
  if (uri.host != 'mereytoi.kz') return null;
  final segments = uri.pathSegments;
  if (segments.length != 2 || segments[0] != 'claim') return null;
  final token = segments[1];
  if (token.isEmpty) return null;
  return token;
}
