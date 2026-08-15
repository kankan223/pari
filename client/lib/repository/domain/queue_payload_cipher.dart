import 'dart:typed_data';

/// Port for encrypting queued payloads before storage (Task 3.3).
///
/// SECURITY CHECKPOINT: queued payloads are STRICTLY encrypted before they
/// are stored. Every mutation that enters the sync queue passes through
/// [seal] — the queue repository persists only ciphertext. [open] recovers
/// the original payload at sync time (inside the encrypted local database),
/// never on the network.
///
/// The concrete implementation uses AES-256-GCM with the Argon2id-derived
/// database key (data layer), so queue payloads share the same key
/// hierarchy as the SQLCipher database itself.
abstract class QueuePayloadCipher {
  /// Encrypts [plaintext] into an opaque sealed payload.
  Future<Uint8List> seal(Uint8List plaintext);

  /// Decrypts [sealed] back into the original payload.
  ///
  /// Throws on authentication failure (wrong key or tampered data).
  Future<Uint8List> open(Uint8List sealed);
}
