import 'double_ratchet_service.dart';

/// Storage port for Double Ratchet sessions (Task 6.3).
///
/// Sessions are keyed by the peer's 64-hex blind hash — never by a phone
/// number, username, or any PII. The data-layer implementation may back this
/// with SQLCipher (durable across restarts) or memory (dev/tests).
abstract class SessionStore {
  /// Loads the session for [peerBlindHash], or null when none exists.
  Future<DoubleRatchetService?> load(String peerBlindHash);

  /// Persists (or replaces) the session for [peerBlindHash].
  Future<void> save(String peerBlindHash, DoubleRatchetService session);

  /// Removes the session for [peerBlindHash] (deletion/duress).
  Future<void> delete(String peerBlindHash);
}

/// In-memory [SessionStore] — safe default for dev/tests.
///
/// SECURITY CHECKPOINT (Task 6.3): keys are blind hashes only; sessions never
/// leave the process, and nothing here is ever logged or persisted in
/// plaintext.
class InMemorySessionStore implements SessionStore {
  final Map<String, DoubleRatchetService> _sessions = {};

  @override
  Future<DoubleRatchetService?> load(String peerBlindHash) async =>
      _sessions[peerBlindHash];

  @override
  Future<void> save(String peerBlindHash, DoubleRatchetService session) async {
    _sessions[peerBlindHash] = session;
  }

  @override
  Future<void> delete(String peerBlindHash) async {
    _sessions.remove(peerBlindHash);
  }
}
