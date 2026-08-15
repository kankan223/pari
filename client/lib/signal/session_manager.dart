import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../crypto/crypto_service.dart';
import 'double_ratchet_service.dart';
import 'models.dart';
import 'session_store.dart';
import 'x3dh_service.dart';

/// Orchestrates X3DH session establishment and per-peer Double Ratchet
/// message sealing (Task 6.3).
///
/// This is the CLIENT-side key-exchange and message-cipher entry point wired
/// into the connection-approval hook (Task 6.2 deferral): when a connection
/// request is accepted, [establishInitiatorSession] runs X3DH with the peer's
/// published prekey bundle to derive the shared secret, initializes a
/// [DoubleRatchetService], and stores the session keyed by the peer's blind
/// hash. [encrypt]/[decrypt] then seal/verify message bodies.
///
/// SECURITY CHECKPOINT (Task 6.3):
/// - Sessions are keyed by 64-hex blind hashes — no phones, no usernames.
/// - Message bodies are sealed with AES-256-GCM via the Double Ratchet; the
///   plaintext exists only transiently inside [encrypt]/[decrypt].
/// - Nothing here is ever logged; no raw payloads escape the process.
class SessionManager {
  final X3DHService _x3dh;
  final CryptoService _crypto;
  final SessionStore _store;

  SessionManager({
    required X3DHService x3dh,
    required CryptoService crypto,
    required SessionStore store,
  })  : _x3dh = x3dh,
        _crypto = crypto,
        _store = store;

  /// Whether a session with [peerBlindHash] is established.
  Future<bool> hasSession(String peerBlindHash) async =>
      await _store.load(peerBlindHash) != null;

  /// Establishes a session as the INITIATOR: X3DH with the peer's
  /// [bundle] using [myIdentityKeyPair], then a fresh Double Ratchet.
  Future<void> establishInitiatorSession({
    required String peerBlindHash,
    required PreKeyBundle bundle,
    required SimpleKeyPair myIdentityKeyPair,
  }) async {
    final sharedSecret = await _x3dh.initiateX3DH(bundle, myIdentityKeyPair);
    final session = DoubleRatchetService(cryptoService: _crypto);
    await session.initialize(sharedSecret);
    await _store.save(peerBlindHash, session);
  }

  /// Establishes a session as the RESPONDER: X3DH response using our
  /// [myIdentityKeyPair] + [signedPreKey] (+ optional [oneTimePreKey]),
  /// then a fresh Double Ratchet.
  Future<void> establishResponderSession({
    required String peerBlindHash,
    required Uint8List initiatorEphemeralPublicKey,
    required SimpleKeyPair myIdentityKeyPair,
    required SignedPreKey signedPreKey,
    OneTimePreKey? oneTimePreKey,
  }) async {
    final sharedSecret = await _x3dh.respondToX3DH(
      initiatorEphemeralPublicKey,
      myIdentityKeyPair,
      signedPreKey,
      oneTimePreKey,
    );
    final session = DoubleRatchetService(cryptoService: _crypto);
    await session.initialize(sharedSecret);
    await _store.save(peerBlindHash, session);
  }

  /// Seals [plaintext] for [peerBlindHash]. Throws [StateError] when no
  /// session is established.
  Future<Uint8List> encrypt({
    required String peerBlindHash,
    required Uint8List plaintext,
  }) async {
    final session = await _requireSession(peerBlindHash);
    final sealed = await session.encrypt(plaintext);
    return sealed.toBytes();
  }

  /// Opens [ciphertext] from [peerBlindHash]. Throws [StateError] when no
  /// session is established; throws the ratchet's error when the MAC fails
  /// (tampered/out-of-order) — callers map that to a placeholder.
  Future<Uint8List> decrypt({
    required String peerBlindHash,
    required Uint8List ciphertext,
  }) async {
    final session = await _requireSession(peerBlindHash);
    return session.decrypt(EncryptedMessage.fromBytes(ciphertext));
  }

  /// Removes the session for [peerBlindHash] (duress / account deletion).
  Future<void> deleteSession(String peerBlindHash) =>
      _store.delete(peerBlindHash);

  Future<DoubleRatchetService> _requireSession(String peerBlindHash) async {
    final session = await _store.load(peerBlindHash);
    if (session == null) {
      throw StateError('No session established for peer');
    }
    return session;
  }
}
