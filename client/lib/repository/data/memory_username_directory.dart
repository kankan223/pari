import '../domain/username_directory.dart';

/// In-memory [UsernameDirectory] (data layer, Task 6.2).
///
/// Dev/test seam: remembers discovered username ↔ blind-hash mappings for
/// the session so the Vault can render `@username` handles. The production
/// implementation persists in the encrypted SQLCipher `users` table.
class MemoryUsernameDirectory implements UsernameDirectory {
  final Map<String, String> _byHash = {};

  MemoryUsernameDirectory([Map<String, String>? seed]) {
    if (seed != null) {
      _byHash.addAll(seed);
    }
  }

  @override
  Future<String?> usernameForHash(String blindHashId) async =>
      _byHash[blindHashId];

  @override
  Future<void> remember({
    required String username,
    required String blindHashId,
  }) async {
    _byHash[blindHashId] = username;
  }
}
