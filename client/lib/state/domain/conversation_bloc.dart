import 'conversation_state.dart';

/// BLoC (Business Logic Component) for the conversation list (Task 3.5).
///
/// Exposes a stream of [ConversationState] derived from the local database's
/// [LocalDataStream]. The UI binds to [state] and never talks to the
/// repository or network directly (offline-first).
///
/// SECURITY (Task 3.5): [ConversationState] carries only UI-safe summaries —
/// never session ciphertext, never decrypted content, never raw payloads.
abstract class ConversationBloc {
  /// Stream of conversation states (initial + every database change).
  Stream<ConversationState> get state;

  /// Starts listening to the local database stream and emits the current
  /// snapshot. Must be called once before reading [state].
  Future<void> start();

  /// Re-reads the local database and emits a fresh snapshot.
  Future<void> refresh();

  /// Releases resources.
  Future<void> close();
}
