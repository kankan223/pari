import 'dart:typed_data';

/// Port for encrypting/decrypting Vault message bodies (Task 6.3).
///
/// The BLoC depends on this abstract interface only; the concrete
/// implementation wraps the signal layer's [SessionManager] (X3DH + Double
/// Ratchet). All operations are keyed by the peer's 64-hex blind hash —
/// never by a phone number, username, or other PII.
abstract class MessageCipher {
  /// Seals [plaintext] for the peer identified by [participantHash].
  ///
  /// Throws [StateError] when no session is established with the peer (the
  /// composer must surface that a session is required before sending).
  Future<Uint8List> encrypt({
    required String participantHash,
    required Uint8List plaintext,
  });

  /// Opens [ciphertext] from the peer identified by [participantHash].
  ///
  /// Returns null when the message cannot be decrypted (no session, tampered
  /// MAC, out-of-order ratchet state) — the UI then shows the fixed
  /// "[end-to-end encrypted]" placeholder. Never throws for a data failure.
  Future<Uint8List?> decrypt({
    required String participantHash,
    required Uint8List ciphertext,
  });
}
