import 'message_state.dart';

/// BLoC (Business Logic Component) for a conversation's message thread
/// (Task 3.5).
///
/// Streams [MessageState] derived from the local database's [LocalDataStream]
/// for a specific [conversationId]. The UI binds to [state] only.
///
/// SECURITY (Task 3.5): [MessageState] carries UI-safe summaries — message
/// ids and delivery flags — NEVER [Message.ciphertext] and never decrypted
/// content, so raw data cannot be exposed or logged through state.
abstract class MessageBloc {
  /// Stream of message states (initial + every database change).
  Stream<MessageState> get state;

  /// Starts listening to the local database stream and emits the current
  /// snapshot. Must be called once before reading [state].
  Future<void> start();

  /// Re-reads the local database and emits a fresh snapshot.
  Future<void> refresh();

  /// Encrypts [text] for the conversation's peer, persists it locally
  /// (offline-first: delivered = false, queued for sync), and republishes
  /// the thread (Task 6.3).
  ///
  /// Throws [StateError] when message encryption is not wired for the
  /// conversation (no established session) — the composer surfaces that
  /// sending requires an established key-exchange session.
  Future<void> send(String text);

  /// Releases resources.
  Future<void> close();
}
