/// Emits snapshots of an entity collection from the local database.
///
/// This is how BLoCs observe the local database WITHOUT polling: the
/// repository layer (or a SQLCipher change notifier) pushes snapshots here,
/// and BLoCs map each snapshot to UI state.
///
/// The concrete implementations live in the data layer; tests use a
/// scripted controller. BLoCs depend only on this abstract interface.
abstract class LocalDataStream<T> {
  /// Stream of collection snapshots (each emission is a full snapshot).
  Stream<List<T>> get changes;
}
