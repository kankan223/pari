/// Local cache mapping blind_hash_id → public username (port, Task 6.2).
///
/// Once a username is discovered via search (or a request is received), the
/// client remembers the mapping so the Vault can render `@username` instead
/// of a derived handle — while STILL never rendering the raw blind hash.
///
/// The production implementation persists in the encrypted SQLCipher
/// `users` table (data layer); tests use an in-memory fake. Either way the
/// values stored are the PUBLIC username + the blind hash — never a phone.
abstract class UsernameDirectory {
  /// Returns the remembered public username for [blindHashId], or null.
  Future<String?> usernameForHash(String blindHashId);

  /// Remembers the [username] ↔ [blindHashId] mapping.
  Future<void> remember({
    required String username,
    required String blindHashId,
  });
}
