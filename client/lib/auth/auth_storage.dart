import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure storage for authentication state.
///
/// Stores access token, refresh token, and username in hardware-backed
/// secure storage. Raw phone numbers are NEVER stored.
///
/// SECURITY: This is the ONLY place tokens are persisted. All reads
/// go through this class — no caching, no logging, no plaintext.
class AuthStorage {
  final FlutterSecureStorage _secureStorage;

  static const _accessTokenKey = 'auth_access_token';
  static const _refreshTokenKey = 'auth_refresh_token';
  static const _blindHashIdKey = 'auth_blind_hash_id';
  static const _usernameKey = 'auth_username';
  static const _avatarUrlKey = 'auth_avatar_url';
  static const _statusTextKey = 'auth_status_text';
  static const _statusVisibilityKey = 'auth_status_visibility';

  AuthStorage({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  /// Check if the user is authenticated (has access token).
  Future<bool> isAuthenticated() async {
    final token = await _secureStorage.read(key: _accessTokenKey);
    return token != null && token.isNotEmpty;
  }

  /// Get the stored access token.
  Future<String?> getAccessToken() async {
    return _secureStorage.read(key: _accessTokenKey);
  }

  /// Get the stored refresh token.
  Future<String?> getRefreshToken() async {
    return _secureStorage.read(key: _refreshTokenKey);
  }

  /// Get the stored blind hash ID.
  Future<String?> getBlindHashId() async {
    return _secureStorage.read(key: _blindHashIdKey);
  }

  /// Get the stored username.
  Future<String?> getUsername() async {
    return _secureStorage.read(key: _usernameKey);
  }

  /// Save auth tokens after successful OTP verification.
  Future<void> saveAuthTokens({
    required String accessToken,
    required String refreshToken,
    required String blindHashId,
  }) async {
    await Future.wait([
      _secureStorage.write(key: _accessTokenKey, value: accessToken),
      _secureStorage.write(key: _refreshTokenKey, value: refreshToken),
      _secureStorage.write(key: _blindHashIdKey, value: blindHashId),
    ]);
  }

  /// Save the claimed username.
  Future<void> saveUsername(String username) async {
    await _secureStorage.write(key: _usernameKey, value: username);
  }

  /// Get the stored avatar URL.
  Future<String?> getAvatarUrl() async {
    return _secureStorage.read(key: _avatarUrlKey);
  }

  /// Save avatar URL.
  Future<void> saveAvatarUrl(String url) async {
    await _secureStorage.write(key: _avatarUrlKey, value: url);
  }

  /// Get the stored status text.
  Future<String?> getStatusText() async {
    return _secureStorage.read(key: _statusTextKey);
  }

  /// Save status text.
  Future<void> saveStatusText(String text) async {
    await _secureStorage.write(key: _statusTextKey, value: text);
  }

  /// Get the stored status visibility.
  Future<String?> getStatusVisibility() async {
    return _secureStorage.read(key: _statusVisibilityKey);
  }

  /// Save status visibility.
  Future<void> saveStatusVisibility(String visibility) async {
    await _secureStorage.write(key: _statusVisibilityKey, value: visibility);
  }

  /// Clear all auth state (logout).
  Future<void> clearAll() async {
    await Future.wait([
      _secureStorage.delete(key: _accessTokenKey),
      _secureStorage.delete(key: _refreshTokenKey),
      _secureStorage.delete(key: _blindHashIdKey),
      _secureStorage.delete(key: _usernameKey),
      _secureStorage.delete(key: _avatarUrlKey),
      _secureStorage.delete(key: _statusTextKey),
      _secureStorage.delete(key: _statusVisibilityKey),
    ]);
  }

  /// Get a summary of the current auth state (for debugging only — no PII).
  Future<Map<String, dynamic>> debugSummary() async {
    return {
      'hasAccessToken': await _secureStorage.read(key: _accessTokenKey) != null,
      'hasRefreshToken':
          await _secureStorage.read(key: _refreshTokenKey) != null,
      'hasBlindHashId':
          await _secureStorage.read(key: _blindHashIdKey) != null,
      'username': await _secureStorage.read(key: _usernameKey),
    };
  }
}
