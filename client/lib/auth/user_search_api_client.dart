import 'dart:convert';

import 'package:http/http.dart' as http;

import '../repository/domain/user_list_result.dart';
import '../repository/domain/username_lookup_result.dart';

/// HTTP client for the Civic Commons identity service's username search.
///
/// Calls `GET /v1/identity/username/{username}` which returns the public
/// username and the owner's blind hash — the minimum needed to start a
/// conversation.
///
/// SECURITY: This client lives in lib/auth/ — it is the ONLY networking
/// layer for username search. Domain, data, and UI layers must never
/// import dart:io or http directly.
class UserSearchApiClient {
  final String baseUrl;
  final http.Client _client;

  UserSearchApiClient({
    required this.baseUrl,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Search for a user by [username].
  ///
  /// Returns the [UsernameLookupResult] on success, or null if the
  /// username doesn't exist.
  Future<UsernameLookupResult?> searchByUsername({
    required String accessToken,
    required String username,
  }) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/v1/identity/username/$username'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return UsernameLookupResult(
        username: body['username'] as String,
        blindHashId: body['blind_hash_id'] as String,
      );
    }

    // 404 = username not found. 401 = token expired. Both return null
    // to keep the domain layer PII-free (no error envelopes).
    return null;
  }

  /// Lists users who have claimed a username, with pagination.
  ///
  /// Returns a [UserListResult] containing the page of users, total count,
  /// and whether more pages exist.
  Future<UserListResult> listUsers({
    required String accessToken,
    int limit = 50,
    int offset = 0,
  }) async {
    final uri = Uri.parse('$baseUrl/v1/identity/users').replace(
      queryParameters: {
        'limit': limit.toString(),
        'offset': offset.toString(),
      },
    );
    final response = await _client.get(
      uri,
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final users = body['users'] as List<dynamic>? ?? [];
      return UserListResult(
        users: users.map((u) {
          final map = u as Map<String, dynamic>;
          return UsernameLookupResult(
            username: map['username'] as String,
            blindHashId: map['blind_hash_id'] as String,
          );
        }).toList(),
        total: body['total'] as int? ?? 0,
        hasMore: body['has_more'] as bool? ?? false,
      );
    }
    return const UserListResult(users: [], total: 0, hasMore: false);
  }

  void dispose() {
    _client.close();
  }
}
