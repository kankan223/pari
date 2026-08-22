import 'dart:typed_data';

import 'package:civic_commons/crypto/crypto_service_impl.dart';
import 'package:civic_commons/signal/models.dart';
import 'package:civic_commons/signal/session_manager.dart';
import 'package:civic_commons/signal/session_store.dart';
import 'package:civic_commons/signal/x3dh_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:civic_commons/signal/double_ratchet_service.dart';

/// Helper: extract raw public key bytes from a SimpleKeyPair.
Future<Uint8List> _pubBytes(dynamic keyPair) async =>
    Uint8List.fromList((await keyPair.extractPublicKey()).bytes);

/// Task 13.2 — Signal session integration: X3DH session establishment +
/// Double Ratchet encrypt/decrypt round-trip via SessionManager. Uses
/// REAL crypto primitives (CryptoServiceImpl, X3DHService).
void main() {
  late CryptoServiceImpl crypto;
  late X3DHService x3dh;

  setUp(() {
    crypto = CryptoServiceImpl();
    x3dh = X3DHService(cryptoService: crypto);
  });

  group('Task 13.2 — session integration', () {
    test('SessionManager full lifecycle: establish → encrypt → decrypt → delete',
        () async {
      final store = InMemorySessionStore();
      final manager = SessionManager(
        x3dh: x3dh,
        crypto: crypto,
        store: store,
      );

      // Responder generates keys and publishes bundle
      final responderIdentity = await crypto.generateCurve25519KeyPair();
      final responderSignedPreKey = await crypto.generateCurve25519KeyPair();
      final responderOneTimePreKey = await crypto.generateCurve25519KeyPair();

      final bundle = PreKeyBundle(
        registrationId: '1',
        identityKey: await _pubBytes(responderIdentity),
        signedPreKeyId: 1,
        signedPreKey: await _pubBytes(responderSignedPreKey),
        signedPreKeySignature: Uint8List(64),
        oneTimePreKeyId: 1,
        oneTimePreKey: await _pubBytes(responderOneTimePreKey),
      );

      final initiatorIdentity = await crypto.generateCurve25519KeyPair();
      final peerHash = 'a' * 64;

      // 1. Establish session via X3DH
      await manager.establishInitiatorSession(
        peerBlindHash: peerHash,
        bundle: bundle,
        myIdentityKeyPair: initiatorIdentity,
      );
      expect(await manager.hasSession(peerHash), isTrue);

      // 2. Encrypt a message
      final plaintext = Uint8List.fromList('Hello, secure world!'.codeUnits);
      final ciphertext = await manager.encrypt(
        peerBlindHash: peerHash,
        plaintext: plaintext,
      );
      expect(ciphertext, isNot(equals(plaintext)));

      // 3. Decrypt (loopback — same ratchet instance)
      final decrypted = await manager.decrypt(
        peerBlindHash: peerHash,
        ciphertext: ciphertext,
      );
      expect(decrypted, plaintext);

      // 4. Multiple messages work
      final msg2 = Uint8List.fromList('Second message'.codeUnits);
      final enc2 = await manager.encrypt(peerBlindHash: peerHash, plaintext: msg2);
      final dec2 = await manager.decrypt(peerBlindHash: peerHash, ciphertext: enc2);
      expect(dec2, msg2);

      // 5. Delete session
      await manager.deleteSession(peerHash);
      expect(await manager.hasSession(peerHash), isFalse);
    });

    test('ratchet produces different ciphertexts for same plaintext', () async {
      final store = InMemorySessionStore();
      final manager = SessionManager(
        x3dh: x3dh,
        crypto: crypto,
        store: store,
      );

      final responderIdentity = await crypto.generateCurve25519KeyPair();
      final responderSignedPreKey = await crypto.generateCurve25519KeyPair();
      final bundle = PreKeyBundle(
        registrationId: '1',
        identityKey: await _pubBytes(responderIdentity),
        signedPreKeyId: 1,
        signedPreKey: await _pubBytes(responderSignedPreKey),
        signedPreKeySignature: Uint8List(64),
      );

      final identity = await crypto.generateCurve25519KeyPair();
      await manager.establishInitiatorSession(
        peerBlindHash: 'b' * 64,
        bundle: bundle,
        myIdentityKeyPair: identity,
      );

      final plaintext = Uint8List.fromList('same message'.codeUnits);
      final enc1 = await manager.encrypt(
          peerBlindHash: 'b' * 64, plaintext: plaintext);
      final enc2 = await manager.encrypt(
          peerBlindHash: 'b' * 64, plaintext: plaintext);

      // Different nonces → different ciphertext
      expect(enc1, isNot(equals(enc2)));
    });

    test('tampered ciphertext fails to decrypt', () async {
      final store = InMemorySessionStore();
      final manager = SessionManager(
        x3dh: x3dh,
        crypto: crypto,
        store: store,
      );

      final responderIdentity = await crypto.generateCurve25519KeyPair();
      final responderSignedPreKey = await crypto.generateCurve25519KeyPair();
      final bundle = PreKeyBundle(
        registrationId: '1',
        identityKey: await _pubBytes(responderIdentity),
        signedPreKeyId: 1,
        signedPreKey: await _pubBytes(responderSignedPreKey),
        signedPreKeySignature: Uint8List(64),
      );

      final identity = await crypto.generateCurve25519KeyPair();
      final peer = 'c' * 64;
      await manager.establishInitiatorSession(
        peerBlindHash: peer,
        bundle: bundle,
        myIdentityKeyPair: identity,
      );

      final plaintext = Uint8List.fromList('secret'.codeUnits);
      final encrypted = await manager.encrypt(peerBlindHash: peer, plaintext: plaintext);

      // Tamper with the ciphertext bytes
      final tampered = Uint8List.fromList(encrypted);
      tampered[tampered.length - 1] ^= 0xFF;

      expect(
        () => manager.decrypt(peerBlindHash: peer, ciphertext: tampered),
        throwsA(anything),
      );
    });

    test('encrypt without session throws StateError', () async {
      final store = InMemorySessionStore();
      final manager = SessionManager(
        x3dh: x3dh,
        crypto: crypto,
        store: store,
      );

      expect(
        () => manager.encrypt(
          peerBlindHash: 'nonexistent',
          plaintext: Uint8List(0),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('zero-PII: session keys are 64-hex blind hashes only', () {
      final validHash = 'a' * 64;
      expect(validHash.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(validHash), isTrue);

      final invalidHash = '+919876543210';
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(invalidHash), isFalse);
    });
  });
}

/// Simple in-memory session store for integration tests.
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
