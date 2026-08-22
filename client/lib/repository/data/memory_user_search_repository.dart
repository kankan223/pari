import '../domain/user_search_repository.dart';
import '../domain/username_lookup_result.dart';

/// In-memory [UserSearchRepository] (data layer, Task 6.2).
///
/// Dev/test seam until the gateway transport lands (the production impl
/// calls `GET /v1/identity/username/{username}` through the API Gateway).
/// Seedable so tests can script the directory of known usernames.
///
/// SECURITY CHECKPOINT (Task 6.2): the seed map keys are public usernames
/// and values are 64-hex blind hashes — a phone number can never be seeded
/// or returned. The query surface is exact-match on username only.
class MemoryUserSearchRepository implements UserSearchRepository {
  final Map<String, String> _directory = {};

  MemoryUserSearchRepository([Map<String, String>? seed]) {
    if (seed != null) {
      _directory.addAll(seed);
    }
  }

  /// Seeds (or overwrites) a username → blind-hash mapping.
  void seed(String username, String blindHashId) {
    _directory[username] = blindHashId;
  }

  @override
  Future<UsernameLookupResult?> searchByUsername(String username) async {
    final hash = _directory[username];
    if (hash == null) {
      return null;
    }
    return UsernameLookupResult(username: username, blindHashId: hash);
  }

  @override
  Future<List<UsernameLookupResult>> listUsers() async {
    final entries = _directory.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries
        .map((e) => UsernameLookupResult(username: e.key, blindHashId: e.value))
        .toList();
  }
}
