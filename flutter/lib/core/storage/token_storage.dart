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

  static final TokenStorage instance = TokenStorage._internal(
    const FlutterSecureStorage(),
  );

  final FlutterSecureStorage _storage;

  static const _tokenKey = 'mereytoi_auth_token';

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  Future<void> clearToken() => _storage.delete(key: _tokenKey);
}
