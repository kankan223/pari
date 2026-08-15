import 'dart:typed_data';

import 'package:civic_commons/crypto/crypto_service.dart';
import 'package:civic_commons/crypto/crypto_service_impl.dart';
import 'package:civic_commons/signal/models.dart';
import 'package:civic_commons/signal/session_manager.dart';
import 'package:civic_commons/signal/session_store.dart';
import 'package:civic_commons/signal/x3dh_service.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> _pubBytes(SimpleKeyPair keyPair) async =>
    Uint8List.fromList((await keyPair.extractPublicKey()).bytes);

void main() {
  late CryptoService crypto;
  late SessionManager manager;

  setUp(() {
    crypto = CryptoServiceImpl();
    manager = SessionManager(
      x3dh: X3DHService(cryptoService: crypto),
      crypto: crypto,
      store: InMemorySessionStore(),
    );
  });

  /// Builds a peer prekey bundle from freshly generated recipient keys.
  Future<PreKeyBundle> buildPeerBundle({
    required SimpleKeyPair recipientIdentityKey,
    required SimpleKeyPair recipientSignedPreKey,
    SimpleKeyPair? recipientOneTimePreKey,
  }) async {
    return PreKeyBundle(
      registrationId: '12345',
      identityKey: await _pubBytes(recipientIdentityKey),
      signedPreKeyId: 1,
      signedPreKey: await _pubBytes(recipientSignedPreKey),
      signedPreKeySignature: Uint8List(64),
      oneTimePreKeyId: recipientOneTimePreKey == null ? null : 1,
      oneTimePreKey: recipientOneTimePreKey == null
          ? null
          : await _pubBytes(recipientOneTimePreKey),
    );
  }

  group('SessionManager - X3DH establishment (Task 6.3)', () {
    test('establishInitiatorSession stores a session for the peer hash',
        () async {
      final identity = await crypto.generateEd25519KeyPair();
      final signedPreKey = await crypto.generateCurve25519KeyPair();
      final bundle = await buildPeerBundle(
        recipientIdentityKey: identity,
        recipientSignedPreKey: signedPreKey,
      );

      await manager.establishInitiatorSession(
        peerBlindHash: 'a' * 64,
        bundle: bundle,
        myIdentityKeyPair: identity,
      );

      expect(await manager.hasSession('a' * 64), isTrue);
      expect(await manager.hasSession('b' * 64), isFalse);
    });

    test('establishInitiatorSession with a one-time prekey also succeeds',
        () async {
      final identity = await crypto.generateEd25519KeyPair();
      final signedPreKey = await crypto.generateCurve25519KeyPair();
      final oneTimePreKey = await crypto.generateCurve25519KeyPair();
      final bundle = await buildPeerBundle(
        recipientIdentityKey: identity,
        recipientSignedPreKey: signedPreKey,
        recipientOneTimePreKey: oneTimePreKey,
      );

      await manager.establishInitiatorSession(
        peerBlindHash: 'a' * 64,
        bundle: bundle,
        myIdentityKeyPair: identity,
      );

      expect(await manager.hasSession('a' * 64), isTrue);
    });

    test('establishResponderSession stores a session for the peer hash',
        () async {
      final myIdentity = await crypto.generateEd25519KeyPair();
      final mySignedPreKey = await crypto.generateCurve25519KeyPair();
      final signedPreKey = SignedPreKey(
        keyId: 1,
        publicKey: await _pubBytes(mySignedPreKey),
        privateKey:
            Uint8List.fromList(await mySignedPreKey.extractPrivateKeyBytes()),
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(days: 7)),
      );
      final initiatorEphemeral =
          Uint8List.fromList(List.generate(32, (i) => i));

      await manager.establishResponderSession(
        peerBlindHash: 'b' * 64,
        initiatorEphemeralPublicKey: initiatorEphemeral,
        myIdentityKeyPair: myIdentity,
        signedPreKey: signedPreKey,
      );

      expect(await manager.hasSession('b' * 64), isTrue);
    });
  });

  group('SessionManager - encrypt/decrypt (Task 6.3)', () {
    test('a message round-trips through the established session', () async {
      final identity = await crypto.generateEd25519KeyPair();
      final signedPreKey = await crypto.generateCurve25519KeyPair();
      final bundle = await buildPeerBundle(
        recipientIdentityKey: identity,
        recipientSignedPreKey: signedPreKey,
      );
      await manager.establishInitiatorSession(
        peerBlindHash: 'a' * 64,
        bundle: bundle,
        myIdentityKeyPair: identity,
      );

      final plaintext = Uint8List.fromList('Hello, Vault!'.codeUnits);
      final sealed = await manager.encrypt(
        peerBlindHash: 'a' * 64,
        plaintext: plaintext,
      );
      final opened = await manager.decrypt(
        peerBlindHash: 'a' * 64,
        ciphertext: sealed,
      );

      expect(opened, equals(plaintext));
      // Sealed bytes are opaque and never equal the plaintext.
      expect(sealed, isNot(equals(plaintext)));
    });

    test('ciphertext for the same plaintext differs across messages', () async {
      final identity = await crypto.generateEd25519KeyPair();
      final signedPreKey = await crypto.generateCurve25519KeyPair();
      final bundle = await buildPeerBundle(
        recipientIdentityKey: identity,
        recipientSignedPreKey: signedPreKey,
      );
      await manager.establishInitiatorSession(
        peerBlindHash: 'a' * 64,
        bundle: bundle,
        myIdentityKeyPair: identity,
      );
      final plaintext = Uint8List.fromList('same text'.codeUnits);

      final first = await manager.encrypt(
        peerBlindHash: 'a' * 64,
        plaintext: plaintext,
      );
      final second = await manager.encrypt(
        peerBlindHash: 'a' * 64,
        plaintext: plaintext,
      );

      expect(first, isNot(equals(second)));
    });

    test('encrypt without a session throws StateError', () async {
      expect(
        () => manager.encrypt(
          peerBlindHash: 'a' * 64,
          plaintext: Uint8List.fromList([1, 2, 3]),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('decrypt without a session throws StateError', () async {
      expect(
        () => manager.decrypt(
          peerBlindHash: 'a' * 64,
          ciphertext: Uint8List.fromList([1, 2, 3]),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('SessionManager - lifecycle & isolation (Task 6.3)', () {
    test('sessions are isolated per peer blind hash', () async {
      final identityA = await crypto.generateEd25519KeyPair();
      final signedPreKeyA = await crypto.generateCurve25519KeyPair();
      final bundleA = await buildPeerBundle(
        recipientIdentityKey: identityA,
        recipientSignedPreKey: signedPreKeyA,
      );
      await manager.establishInitiatorSession(
        peerBlindHash: 'a' * 64,
        bundle: bundleA,
        myIdentityKeyPair: identityA,
      );

      // Peer B has no session — nothing leaks across peers.
      expect(await manager.hasSession('a' * 64), isTrue);
      expect(await manager.hasSession('b' * 64), isFalse);
      expect(
        () => manager.decrypt(
          peerBlindHash: 'b' * 64,
          ciphertext: Uint8List.fromList([1, 2, 3]),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('deleteSession removes the session (duress / deletion)', () async {
      final identity = await crypto.generateEd25519KeyPair();
      final signedPreKey = await crypto.generateCurve25519KeyPair();
      final bundle = await buildPeerBundle(
        recipientIdentityKey: identity,
        recipientSignedPreKey: signedPreKey,
      );
      await manager.establishInitiatorSession(
        peerBlindHash: 'a' * 64,
        bundle: bundle,
        myIdentityKeyPair: identity,
      );

      await manager.deleteSession('a' * 64);

      expect(await manager.hasSession('a' * 64), isFalse);
    });
  });
}
