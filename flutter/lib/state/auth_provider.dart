import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_client.dart';
import '../core/storage/token_storage.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import 'providers.dart';

/// The four states the rest of the app actually needs to branch on. Kept as
/// a small sealed hierarchy (not `AsyncValue<User?>`) because "no session
/// yet" and "an error happened" are genuinely different things here — a
/// failed background session-restore must land on [AuthUnauthenticated]
/// (a normal, expected state, the same as never having logged in), not on
/// some equivalent of `AsyncError` the rest of the app would have to
/// special-case.
sealed class AuthState {
  const AuthState();
}

/// Before the very first session-restore attempt has started. Exists only
/// as [AuthNotifier]'s starting value; nothing in the UI should linger here.
class AuthInitial extends AuthState {
  const AuthInitial();
}

/// Restoring a persisted session at app start (reading the token, then
/// `GET /api/auth/me`) — *not* reused for login/register submissions,
/// which have their own ephemeral [authSubmitProvider] loading state so a
/// failed login attempt never has to fight over the same flag as "is there
/// a session".
class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.user);
  final User user;
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

/// Owns the session lifecycle end to end: restore-on-start, login, register,
/// logout, and reacting to a 401 from anywhere else in the app.
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._authService) : super(const AuthInitial()) {
    // One-time wiring: ApiClient reports "a request just came back 401" as
    // a plain callback (see ApiClient's own doc comment on why it isn't a
    // Riverpod dependency) — this is the one place that turns that into an
    // actual session change.
    ApiClient.instance.setUnauthorizedHandler(_handleUnauthorized);
    _restoreSession();
  }

  final AuthService _authService;

  /// 1. read the persisted token: none → guest, done.
  /// 2. token found → GET /api/auth/me to confirm it's still valid.
  /// 3. valid → authenticated with the fresh user record.
  /// 4. rejected (401) or any other failure → treat exactly like "no
  ///    session" (clearing a token that turned out to be dead is the
  ///    correct outcome either way; a transient network hiccup at startup
  ///    just means the app opens in guest mode, same as the site's own
  ///    AuthContext bootstrap falling back to logged-out on a failed
  ///    `/me` call).
  Future<void> _restoreSession() async {
    state = const AuthLoading();
    final token = await TokenStorage.instance.readToken();
    if (token == null || token.isEmpty) {
      state = const AuthUnauthenticated();
      return;
    }
    try {
      final user = await _authService.fetchMe();
      state = AuthAuthenticated(user);
    } catch (_) {
      await TokenStorage.instance.clearToken();
      state = const AuthUnauthenticated();
    }
  }

  /// Throws (an [ApiException] — see core/network/api_exception.dart) on
  /// failure and leaves [state] untouched; callers (see
  /// [AuthSubmitNotifier]) are expected to catch it and show it inline,
  /// the same pattern `BookingSubmitNotifier` already uses.
  Future<void> login({
    String? email,
    String? phone,
    required String password,
  }) async {
    final result = await _authService.login(
      email: email,
      phone: phone,
      password: password,
    );
    await TokenStorage.instance.saveToken(result.token);
    state = AuthAuthenticated(result.user);
  }

  Future<void> register({
    required String name,
    required String email,
    String phone = '',
    required String password,
  }) async {
    final result = await _authService.register(
      name: name,
      email: email,
      phone: phone,
      password: password,
    );
    await TokenStorage.instance.saveToken(result.token);
    state = AuthAuthenticated(result.user);
  }

  Future<void> logout() async {
    await TokenStorage.instance.clearToken();
    state = const AuthUnauthenticated();
  }

  /// `POST /api/auth/claim/:token` — the pending-account onboarding
  /// bridge (Stage 5). Same session bootstrap as [login]/[register]
  /// (save the token via secure storage, then `AuthAuthenticated`);
  /// returns the additive `eventId` so the claim screen can navigate
  /// straight to that event's workspace. Throws on failure (invalid/
  /// expired/already-used/network) — the claim screen classifies the
  /// [ApiException] itself, this never touches [state] on failure.
  Future<int?> claim(String token) async {
    final result = await _authService.claim(token);
    await TokenStorage.instance.saveToken(result.token);
    state = AuthAuthenticated(result.user);
    return result.eventId;
  }

  /// `PUT /api/auth/me` — updates name/phone, then reflects the saved
  /// result straight into [state] so every screen watching the current
  /// user updates immediately, no separate refetch needed.
  Future<void> updateProfile({required String name, String phone = ''}) async {
    final user = await _authService.updateMe(name: name, phone: phone);
    final current = state;
    // Carries over telegram_linked/preferred_delivery_channel — updateMe's
    // own response never includes those two /me-only sibling fields (see
    // User's own doc comment), so a plain replace would otherwise silently
    // reset them to null on every profile edit.
    state = AuthAuthenticated(
      current is AuthAuthenticated
          ? user.copyWith(
              telegramLinked: current.user.telegramLinked,
              preferredDeliveryChannel: current.user.preferredDeliveryChannel,
            )
          : user,
    );
  }

  /// `PUT /api/users/me/delivery-preference`.
  Future<void> updateDeliveryPreference(String channel) async {
    await _authService.updateDeliveryPreference(channel);
    final current = state;
    if (current is AuthAuthenticated) {
      state = AuthAuthenticated(
        current.user.copyWith(preferredDeliveryChannel: channel),
      );
    }
  }

  /// Re-fetches `GET /api/auth/me` — used after returning from the
  /// Telegram app (linking happens async, via the bot's own webhook, so
  /// this is how the profile screen picks up `telegram_linked` flipping
  /// to `true` once the user has actually pressed Start in the bot).
  Future<void> refreshMe() async {
    final user = await _authService.fetchMe();
    state = AuthAuthenticated(user);
  }

  /// Only actually changes anything if a session was believed to be active
  /// — a 401 from, say, a login attempt with the wrong password fires this
  /// too, but there was never a session to tear down in that case.
  void _handleUnauthorized() {
    if (state is AuthAuthenticated) {
      TokenStorage.instance.clearToken();
      state = const AuthUnauthenticated();
    }
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.watch(authServiceProvider));
});

/// Convenience read used by screens/widgets that only care "is someone
/// logged in right now", without matching on every [AuthState] variant.
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authProvider) is AuthAuthenticated;
});

/// Ephemeral submit state for the Login/Register forms — mirrors
/// `BookingSubmitNotifier` exactly (idle → loading → success/error), kept
/// separate from [authProvider]'s own persistent session state so a failed
/// attempt never has to be represented as some flavor of "unauthenticated"
/// or block whatever the app's real session state already was.
class AuthSubmitNotifier extends StateNotifier<AsyncValue<void>> {
  AuthSubmitNotifier(this._ref) : super(const AsyncData(null));

  final Ref _ref;

  Future<void> login({
    String? email,
    String? phone,
    required String password,
  }) async {
    state = const AsyncLoading();
    try {
      await _ref
          .read(authProvider.notifier)
          .login(email: email, phone: phone, password: password);
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  Future<void> register({
    required String name,
    required String email,
    String phone = '',
    required String password,
  }) async {
    state = const AsyncLoading();
    try {
      await _ref
          .read(authProvider.notifier)
          .register(name: name, email: email, phone: phone, password: password);
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  void reset() => state = const AsyncData(null);
}

final authSubmitProvider =
    StateNotifierProvider.autoDispose<AuthSubmitNotifier, AsyncValue<void>>((
      ref,
    ) {
      return AuthSubmitNotifier(ref);
    });
