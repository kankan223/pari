import 'dart:typed_data';

import '../../signal/session_manager.dart';
import '../domain/message_cipher.dart';

/// [MessageCipher] backed by the signal layer's [SessionManager] (Task 6.3).
///
/// SECURITY CHECKPOINT (Task 6.3): plaintext lives only transiently inside
/// [encrypt]/[decrypt] calls; the cipher is keyed by blind hash; failures map
/// to null (placeholder) instead of leaking error detail or raw bytes.
class SignalMessageCipher implements MessageCipher {
  final SessionManager _sessions;

  SignalMessageCipher({required SessionManager sessions})
      : _sessions = sessions;

  @override
  Future<Uint8List> encrypt({
    required String participantHash,
    required Uint8List plaintext,
  }) =>
      _sessions.encrypt(
        peerBlindHash: participantHash,
        plaintext: plaintext,
      );

  @override
  Future<Uint8List?> decrypt({
    required String participantHash,
    required Uint8List ciphertext,
  }) async {
    try {
      return await _sessions.decrypt(
        peerBlindHash: participantHash,
        ciphertext: ciphertext,
      );
    } catch (_) {
      // No session, tampered MAC, or ratchet skew — the UI falls back to the
      // fixed placeholder. Never propagate raw ciphertext or error detail.
      return null;
    }
  }
}
