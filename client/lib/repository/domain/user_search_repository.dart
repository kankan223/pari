import 'username_lookup_result.dart';

/// The ONLY boundary for username search (port, Task 6.2).
///
/// Mirrors the [SyncSink] convention: repositories never make direct HTTP
/// calls. This injected port performs the actual transport in a later phase
/// (the gateway `GET /v1/identity/username/{username}` endpoint); the data
/// layer today ships an in-memory implementation for dev/tests, and the
/// SQLCipher username cache. Search returns null for "not found" — never a
/// phone number, never an error envelope carrying PII.
abstract class UserSearchRepository {
  /// Resolves [username] to its owner's blind hash, or null when the
  /// username does not resolve (unknown, released, or reserved).
  Future<UsernameLookupResult?> searchByUsername(String username);

  /// Lists all users who have claimed a username.
  Future<List<UsernameLookupResult>> listUsers();
}
