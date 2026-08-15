/// Abstract base repository with standard CRUD operations (Task 3.2).
///
/// Every repository in the app implements this contract. Operations are
/// LOCAL-FIRST: they read/write the encrypted local store only and never
/// perform network I/O directly. Outbound synchronization flows through the
/// injected [SyncSink] port exclusively (SECURITY CHECKPOINT).
abstract class BaseRepository<T> {
  /// Persists a new [entity] to the local store.
  Future<T> create(T entity);

  /// Reads the entity with primary key [id], or null when absent.
  Future<T?> getById(String id);

  /// Reads every stored entity (local snapshot, never a network call).
  Future<List<T>> getAll();

  /// Persists changes to [entity] (same primary key).
  Future<T> update(T entity);

  /// Deletes the entity with primary key [id].
  Future<void> delete(String id);
}
