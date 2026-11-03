import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The one place the JWT session token is read/written — platform
/// keychain-backed (iOS Keychain / Android EncryptedSharedPreferences via
/// flutter_secure_storage), never SharedPreferences and never held only in
/// a plain in-memory variable, so a real session survives an app restart
/// the same way the site's own token survives a page reload
/// (frontend/src/lib/authToken.js's localStorage, just backed by something
/// actually appropriate for a credential on mobile).
class TokenStorage {
  TokenStorage._internal(this._storage);

  @visibleForTesting
  TokenStorage.test(FlutterSecureStorage storage) : this._internal(storage);

  static final TokenStorage instance = TokenStorage._internal(
    const FlutterSecureStorage(),
  );

  final FlutterSecureStorage _storage;

  static const _tokenKey = 'mereytoi_auth_token';

  /// The saved token, or null. Never throws: storage that can't be
  /// decrypted (Android restored the app's encrypted prefs from a Google
  /// backup onto a reinstall, but not the Keystore key that encrypted
  /// them — "BadPaddingException" on every read) is wiped once and read as
  /// "no session". Before, that read failed inside the request interceptor
  /// and turned every request — guest ones too — into «Не удалось
  /// загрузить данные».
  Future<String?> readToken() async {
    try {
      return await _storage.read(key: _tokenKey);
    } catch (e) {
      debugPrint('[token-storage] unreadable (${e.runtimeType}); resetting');
      try {
        await _storage.deleteAll();
      } catch (e2) {
        debugPrint('[token-storage] reset failed (${e2.runtimeType})');
      }
      return null;
    }
  }

  Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  Future<void> clearToken() async {
    try {
      await _storage.delete(key: _tokenKey);
    } catch (e) {
      debugPrint('[token-storage] delete failed (${e.runtimeType})');
    }
  }
}
