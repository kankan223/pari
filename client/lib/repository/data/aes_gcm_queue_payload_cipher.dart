import 'dart:typed_data';

import '../../crypto/crypto_service.dart';
import '../domain/queue_payload_cipher.dart';

/// AES-256-GCM [QueuePayloadCipher] (data layer).
///
/// Reuses the existing [CryptoService] AES-256-GCM implementation with the
/// Argon2id-derived 256-bit database key — the same key hierarchy as the
/// SQLCipher database. Every queued payload is sealed before storage and
/// opened only inside the local app at sync time.
///
/// SECURITY CHECKPOINT (Task 3.3): the queue repository persists ONLY the
/// output of [seal] — plaintext mutation payloads never reach the store.
class AesGcmQueuePayloadCipher implements QueuePayloadCipher {
  final CryptoService _crypto;
  final Uint8List _key;

  /// [key] must be the 32-byte (256-bit) Argon2id-derived database key.
  AesGcmQueuePayloadCipher(
      {required CryptoService crypto, required Uint8List key})
      : _crypto = crypto,
        _key = key {
    if (key.length != 32) {
      throw ArgumentError('Queue payload cipher key must be 32 bytes');
    }
  }

  @override
  Future<Uint8List> seal(Uint8List plaintext) =>
      _crypto.encrypt(plaintext, _key);

  @override
  Future<Uint8List> open(Uint8List sealed) => _crypto.decrypt(sealed, _key);
}
