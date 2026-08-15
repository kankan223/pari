/// Storage boundary (port) for repository persistence.
///
/// Repositories depend ONLY on this abstract interface for local persistence.
/// The production implementation is backed by the encrypted SQLCipher
/// database (data layer); unit tests use in-memory fakes.
///
/// Security contract:
/// - Repositories never receive or return plaintext sensitive values —
///   entities carry only ciphertext, hashes, and opaque payloads.
/// - The whole backing file is encrypted at rest by SQLCipher.
abstract class EntityStore<T> {
  /// Inserts [entity] (or replaces it on primary-key conflict).
  Future<void> insert(T entity);

  /// Updates the stored entity with the same primary key as [entity].
  Future<void> update(T entity);

  /// Deletes the entity with primary key [id].
  Future<void> delete(String id);

  /// Reads the entity with primary key [id], or null when absent.
  Future<T?> getById(String id);

  /// Reads every stored entity (local snapshot).
  Future<List<T>> getAll();
}
