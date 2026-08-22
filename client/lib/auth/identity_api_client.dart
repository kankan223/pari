import 'dart:convert';

import 'package:http/http.dart' as http;

/// HTTP client for the Civic Commons identity service.
///
/// All requests go to the production identity service. Phone numbers
/// are sent only to the OTP request endpoint and never stored locally.
///
/// SECURITY: This client lives in lib/auth/ — it is the ONLY networking
/// layer for identity operations. Domain, data, and UI layers must never
/// import dart:io or http directly.
class IdentityApiClient {
  final String baseUrl;
  final http.Client _client;

  IdentityApiClient({
    required this.baseUrl,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Request an OTP code for [phone] (E.164 format).
  ///
  /// Returns the blind_hash_id on success. The actual OTP is delivered
  /// via SMS (or logged to stdout in noop/dev mode).
  Future<OtpRequestResult> requestOtp(String phone) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/v1/identity/otp/request'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phone': phone}),
    );

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200) {
      return OtpRequestResult(
        blindHashId: body['blind_hash_id'] as String,
        requested: body['requested'] as bool? ?? true,
      );
    }

    throw IdentityApiException(
      statusCode: response.statusCode,
      code: body['error']?['code'] as String? ?? 'unknown',
      message: body['error']?['message'] as String? ?? 'Request failed',
    );
  }

  /// Verify an OTP code for [blindHashId].
  ///
  /// Returns access token, refresh token, and user info on success.
  Future<AuthResult> verifyOtp({
    required String blindHashId,
    required String otp,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/v1/identity/otp/verify'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'blind_hash_id': blindHashId,
        'otp': otp,
      }),
    );

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200) {
      return AuthResult.fromJson(body);
    }

    throw IdentityApiException(
      statusCode: response.statusCode,
      code: body['error']?['code'] as String? ?? 'unknown',
      message: body['error']?['message'] as String? ?? 'Verification failed',
    );
  }

  /// Claim a username for the authenticated identity.
  Future<void> claimUsername({
    required String accessToken,
    required String username,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/v1/identity/username/claim'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({'username': username}),
    );

    if (response.statusCode != 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw IdentityApiException(
        statusCode: response.statusCode,
        code: body['error']?['code'] as String? ?? 'unknown',
        message: body['error']?['message'] as String? ?? 'Claim failed',
      );
    }
  }

  /// Get the current user's profile.
  Future<UserProfile> getMe(String accessToken) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/v1/identity/me'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200) {
      return UserProfile.fromJson(body);
    }

    throw IdentityApiException(
      statusCode: response.statusCode,
      code: body['error']?['code'] as String? ?? 'unknown',
      message: body['error']?['message'] as String? ?? 'Failed to get profile',
    );
  }

  void dispose() {
    _client.close();
  }
}

/// Result of a successful OTP request.
class OtpRequestResult {
  final String blindHashId;
  final bool requested;

  const OtpRequestResult({
    required this.blindHashId,
    required this.requested,
  });
}

/// Result of a successful OTP verification.
class AuthResult {
  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  final UserProfile? user;

  const AuthResult({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    this.user,
  });

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    return AuthResult(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      expiresIn: json['expires_in'] as int,
      user: json['user'] != null
          ? UserProfile.fromJson(json['user'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// User profile from the identity service.
class UserProfile {
  final String blindHashId;
  final String? username;
  final DateTime createdAt;

  const UserProfile({
    required this.blindHashId,
    this.username,
    required this.createdAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      blindHashId: json['blind_hash_id'] as String,
      username: json['username'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// Exception thrown by the identity API.
class IdentityApiException implements Exception {
  final int statusCode;
  final String code;
  final String message;

  const IdentityApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  @override
  String toString() => 'IdentityApiException($statusCode: $code — $message)';
}
