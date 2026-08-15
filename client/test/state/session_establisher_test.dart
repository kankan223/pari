import 'dart:typed_data';

import 'package:civic_commons/crypto/crypto_service.dart';
import 'package:civic_commons/crypto/crypto_service_impl.dart';
import 'package:civic_commons/crypto/secure_key_storage.dart';
import 'package:civic_commons/signal/models.dart';
import 'package:civic_commons/signal/prekey_bundle_source.dart';
import 'package:civic_commons/signal/session_manager.dart';
import 'package:civic_commons/signal/session_store.dart';
import 'package:civic_commons/signal/x3dh_service.dart';
import 'package:civic_commons/state/data/local_session_establisher.dart';
import 'package:civic_commons/state/data/signal_message_cipher.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> _pubBytes(SimpleKeyPair keyPair) async =>
    Uint8List.fromList((await keyPair.extractPublicKey()).bytes);

/// VERIFY (Task 6.3): the connection-approval key-exchange hook establishes
/// an X3DH session keyed by the peer's blind hash, and the message cipher
/// seals/opens bodies through it — with no PII anywhere in the flow.
/// 64-hex blind-hash-shaped test peer.
String peerHash([String prefix = 'a']) => prefix * 64;

void main() {
  late CryptoService crypto;
  late SecureKeyStorage keyStorage;
  late InMemoryPreKeyBundleSource bundles;
  late SessionManager sessions;
  late LocalSessionEstablisher establisher;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    crypto = CryptoServiceImpl();
    keyStorage = SecureKeyStorage();
    bundles = InMemoryPreKeyBundleSource();
    sessions = SessionManager(
      x3dh: X3DHService(cryptoService: crypto),
      crypto: crypto,
      store: InMemorySessionStore(),
    );
    establisher = LocalSessionEstablisher(
      bundleSource: bundles,
      sessions: sessions,
      keyStorage: keyStorage,
      crypto: crypto,
    );
  });

  Future<void> publishBundleFor(String peerHash) async {
    final recipientIdentity = await crypto.generateEd25519KeyPair();
    final recipientSignedPreKey = await crypto.generateCurve25519KeyPair();
    bundles.publish(
      peerHash,
      PreKeyBundle(
        registrationId: '12345',
        identityKey: await _pubBytes(recipientIdentity),
        signedPreKeyId: 1,
        signedPreKey: await _pubBytes(recipientSignedPreKey),
        signedPreKeySignature: Uint8List(64),
      ),
    );
  }

  group('LocalSessionEstablisher - approval hook (Task 6.3)', () {
    test('establishes a session with the peer from their published bundle',
        () async {
      final peer = peerHash();
      await publishBundleFor(peer);

      await establisher.establishWith(peer);

      expect(await sessions.hasSession(peer), isTrue);
    });

    test('is idempotent: an existing session is reused, not re-established',
        () async {
      final peer = peerHash();
      await publishBundleFor(peer);
      await establisher.establishWith(peer);

      await establisher.establishWith(peer);

      expect(await sessions.hasSession(peer), isTrue);
    });

    test('throws when the peer has not published a bundle', () async {
      // No bundle published for this peer.
      await expectLater(
        establisher.establishWith(peerHash()),
        throwsA(isA<StateError>()),
      );
      expect(await sessions.hasSession(peerHash()), isFalse);
    });

    test('creates and stores an identity key pair on first use', () async {
      final peer = peerHash();
      await publishBundleFor(peer);

      expect(await keyStorage.getIdentityKeyPair(), isNull);

      await establisher.establishWith(peer);

      final stored = await keyStorage.getIdentityKeyPair();
      expect(stored, isNotNull);
      expect(await sessions.hasSession(peer), isTrue);
    });
  });

  group('SignalMessageCipher - sealing (Task 6.3)', () {
    test('encrypt + decrypt round-trips a message body', () async {
      final peer = peerHash();
      await publishBundleFor(peer);
      await establisher.establishWith(peer);
      final cipher = SignalMessageCipher(sessions: sessions);

      final plaintext = Uint8List.fromList('Top secret'.codeUnits);
      final sealed = await cipher.encrypt(
        participantHash: peer,
        plaintext: plaintext,
      );
      final opened = await cipher.decrypt(
        participantHash: peer,
        ciphertext: sealed,
      );

      expect(opened, equals(plaintext));
      expect(sealed, isNot(equals(plaintext)));
    });

    test('decrypt returns null (never throws) without a session', () async {
      final cipher = SignalMessageCipher(sessions: sessions);

      final opened = await cipher.decrypt(
        participantHash: peerHash(),
        ciphertext: Uint8List.fromList([1, 2, 3]),
      );

      expect(opened, isNull);
    });
    test('decrypt returns null for tampered ciphertext (never leaks)',
        () async {
      final peer = peerHash();
      await publishBundleFor(peer);
      await establisher.establishWith(peer);
      final cipher = SignalMessageCipher(sessions: sessions);

      final plaintext = Uint8List.fromList('Secret'.codeUnits);
      final sealed = await cipher.encrypt(
        participantHash: peer,
        plaintext: plaintext,
      );
      final tampered = Uint8List.fromList(sealed);
      tampered[tampered.length - 1] ^= 0xff;

      final opened = await cipher.decrypt(
        participantHash: peer,
        ciphertext: tampered,
      );

      expect(opened, isNull);
    });
  });
}
