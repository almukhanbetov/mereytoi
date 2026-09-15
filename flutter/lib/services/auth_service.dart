import '../core/network/api_client.dart';
import '../models/user.dart';

/// `{user, token}` — the exact response shape both
/// `POST /api/auth/login` and `POST /api/auth/register` return.
typedef AuthResult = ({User user, String token});

/// `{user, token, eventId}` — `POST /api/auth/claim/:token`'s response.
/// `eventId` is additive (only present when the newly-claimed account
/// actually owns an event) — never client-chosen, always "whatever event
/// this exact account owns" server-side.
typedef ClaimResult = ({User user, String token, int? eventId});

/// `{configured, linkUrl}` — `POST /api/users/me/telegram/link-token`'s
/// response. `configured: false` (no `link_url` at all) means the backend
/// has no `TELEGRAM_BOT_TOKEN` set — reported honestly rather than handing
/// back a broken link.
typedef TelegramLinkResult = ({bool configured, String? linkUrl});

/// Wraps every real `/api/auth/*` + user-profile endpoint this app uses
/// (backend/internal/handlers/auth_handler.go + telegram_handler.go):
///   POST /api/auth/login | /register            -> {user, token}
///   GET  /api/auth/me                            -> {user, telegram_linked, preferred_delivery_channel}
///   PUT  /api/auth/me            {name, phone}   -> {user}
///   POST /api/auth/claim/:token                  -> {user, token, event_id?}
///   POST /api/auth/claim/resend  {phone}         -> {message} (neutral, never reveals account existence)
///   PUT  /api/users/me/delivery-preference {channel: whatsapp|telegram} -> {preferred_delivery_channel}
///   POST /api/users/me/telegram/link-token       -> {configured, link_url?}
class AuthService {
  AuthService(this._client);

  final ApiClient _client;

  /// Exactly one of [email]/[phone] is expected to be non-empty — mirrors
  /// the site's own login form (frontend/src/lib/authApi.js), which picks
  /// one field based on whether the identifier looks like an email.
  Future<AuthResult> login({
    String? email,
    String? phone,
    required String password,
  }) async {
    final json = await _client.postJson('/api/auth/login', {
      if (email != null && email.isNotEmpty) 'email': email,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      'password': password,
    });
    return _authResultFromJson(json);
  }

  Future<AuthResult> register({
    required String name,
    required String email,
    String phone = '',
    required String password,
  }) async {
    final json = await _client.postJson('/api/auth/register', {
      'name': name,
      'email': email,
      'phone': phone,
      'password': password,
    });
    return _authResultFromJson(json);
  }

  /// `GET /api/auth/me` — requires a token, which `ApiClient`'s own
  /// interceptor attaches automatically; this method never touches the
  /// Authorization header itself. Folds the two `/me`-only sibling fields
  /// onto the returned `User` via `copyWith` (see User's own doc comment).
  Future<User> fetchMe() async {
    final json = await _client.getJson('/api/auth/me');
    final user = User.fromJson(Map<String, dynamic>.from(json['user'] as Map));
    return user.copyWith(
      telegramLinked: json['telegram_linked'] as bool?,
      preferredDeliveryChannel: json['preferred_delivery_channel'] as String?,
    );
  }

  /// `PUT /api/auth/me` — `updateMeInput` on the backend only accepts
  /// name/phone (required name, optional phone); email/password aren't
  /// editable through this endpoint, so nothing here sends them.
  Future<User> updateMe({required String name, String phone = ''}) async {
    final json = await _client.putJson('/api/auth/me', {
      'name': name,
      'phone': phone,
    });
    return User.fromJson(Map<String, dynamic>.from(json['user'] as Map));
  }

  /// `PUT /api/users/me/delivery-preference` — the backend only accepts
  /// `whatsapp`/`telegram` (`binding:"required,oneof=whatsapp telegram"`);
  /// no SMS, never invented here either.
  Future<String> updateDeliveryPreference(String channel) async {
    final json = await _client.putJson('/api/users/me/delivery-preference', {
      'channel': channel,
    });
    return json['preferred_delivery_channel'] as String? ?? channel;
  }

  /// `POST /api/auth/claim/:token` — public (no auth header needed/sent by
  /// the interceptor since there's no session yet); single-use server-side,
  /// so calling this twice with the same token always fails the second time
  /// (`already used`).
  Future<ClaimResult> claim(String token) async {
    final json = await _client.postJson('/api/auth/claim/$token', {});
    final user = User.fromJson(Map<String, dynamic>.from(json['user'] as Map));
    return (
      user: user,
      token: json['token'] as String? ?? '',
      eventId: json['event_id'] as int?,
    );
  }

  /// `POST /api/auth/claim/resend` — always returns the same neutral
  /// message regardless of outcome (brief: never reveal whether a phone
  /// has a pending account), so this returns nothing for the caller to
  /// branch on either.
  Future<void> claimResend(String phone) {
    return _client.postJson('/api/auth/claim/resend', {'phone': phone});
  }

  /// `POST /api/users/me/telegram/link-token` (authenticated).
  Future<TelegramLinkResult> mintTelegramLinkToken() async {
    final json = await _client.postJson(
      '/api/users/me/telegram/link-token',
      {},
    );
    return (
      configured: json['configured'] as bool? ?? false,
      linkUrl: json['link_url'] as String?,
    );
  }

  AuthResult _authResultFromJson(Map<String, dynamic> json) {
    final user = User.fromJson(Map<String, dynamic>.from(json['user'] as Map));
    final token = json['token'] as String? ?? '';
    return (user: user, token: token);
  }
}
