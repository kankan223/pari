import 'dart:typed_data';

/// A Vault conversation (domain entity, Task 3.2).
///
/// Mirrors the `conversations` table in `AppSchema`:
/// - [participantHash] is a blind hash (Argon2id of the participant's phone
///   number) — NEVER a raw phone number.
/// - [encryptedSessionState] is the Signal session state sealed by the crypto
///   layer. This entity NEVER carries plaintext conversation content.
///
/// Security contract: both fields are flagged sensitive in the schema and are
/// only ever stored as opaque ciphertext/hash values inside the encrypted
/// SQLCipher database.
class Conversation {
  final String id;

  /// Blind hash of the peer's phone number (never the raw number).
  final String participantHash;

  /// AES-256-GCM sealed Signal session state (opaque bytes).
  final Uint8List encryptedSessionState;

  const Conversation({
    required this.id,
    required this.participantHash,
    required this.encryptedSessionState,
  });
}
