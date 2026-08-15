/// Port for persisting NON-SENSITIVE state (Task 3.5; boxes in 3.6).
///
/// Only non-sensitive data (UI prefs, ledger drafts metadata, academy
/// progress, karma cache) may use this store. Sensitive data (ciphertext,
/// hashes, keys, PINs) must NEVER be written here — enforce via the schema
/// and review.
///
/// SECURITY CHECKPOINT (Task 3.5): implementations MUST reject/refuse
/// sensitive payloads (defense-in-depth guard) and must never log values.
abstract class NonSensitiveStore {
  /// Reads the value stored under [key], or null when absent.
  Future<String?> read(String key);

  /// Writes [value] under [key].
  Future<void> write(String key, String value);

  /// Removes the value under [key].
  Future<void> delete(String key);

  /// Clears the entire store.
  Future<void> clear();
}
