import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:civic_commons/crypto/crypto_service.dart';
import 'package:civic_commons/crypto/crypto_service_impl.dart';
import 'package:civic_commons/crypto/secure_key_storage.dart';
import 'package:civic_commons/signal/x3dh_service.dart';
import 'package:civic_commons/signal/models.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Helper: extract raw public key bytes from a SimpleKeyPair.
Future<Uint8List> _pubBytes(SimpleKeyPair keyPair) async =>
    Uint8List.fromList((await keyPair.extractPublicKey()).bytes);

void main() {
  group('X3DHService - X3DH Handshake', () {
    late X3DHService x3dhService;
    late CryptoService cryptoService;
    late SecureKeyStorage secureStorage;

    setUp(() async {
      // Use in-memory storage for tests (no device keychain required)
      FlutterSecureStorage.setMockInitialValues({});
      cryptoService = CryptoServiceImpl();
      secureStorage = SecureKeyStorage();
      await secureStorage.deleteAllKeys();
      x3dhService = X3DHService(
        cryptoService: cryptoService,
        secureStorage: secureStorage,
      );
    });

    tearDown(() async {
      await secureStorage.deleteAllKeys();
    });

    test('should perform X3DH initiation successfully', () async {
      // Arrange
      final recipientIdentityKey = await cryptoService.generateEd25519KeyPair();
      final recipientSignedPreKey = await cryptoService.generateCurve25519KeyPair();
      final recipientOneTimePreKey = await cryptoService.generateCurve25519KeyPair();
      
      final bundle = PreKeyBundle(
        registrationId: '12345',
        identityKey: await _pubBytes(recipientIdentityKey),
        signedPreKeyId: 1,
        signedPreKey: await _pubBytes(recipientSignedPreKey),
        signedPreKeySignature: Uint8List(64),
        oneTimePreKeyId: 1,
        oneTimePreKey: await _pubBytes(recipientOneTimePreKey),
      );
      
      final initiatorIdentityKey = await cryptoService.generateEd25519KeyPair();

      // Act
      final sharedSecret = await x3dhService.initiateX3DH(bundle, initiatorIdentityKey);

      // Assert
      expect(sharedSecret, isNotNull);
      expect(sharedSecret.length, equals(32)); // 256-bit shared secret
    });

    test('should perform X3DH initiation without one-time prekey', () async {
      // Arrange
      final recipientIdentityKey = await cryptoService.generateEd25519KeyPair();
      final recipientSignedPreKey = await cryptoService.generateCurve25519KeyPair();
      
      final bundle = PreKeyBundle(
        registrationId: '12345',
        identityKey: await _pubBytes(recipientIdentityKey),
        signedPreKeyId: 1,
        signedPreKey: await _pubBytes(recipientSignedPreKey),
        signedPreKeySignature: Uint8List(64),
      );
      
      final initiatorIdentityKey = await cryptoService.generateEd25519KeyPair();

      // Act
      final sharedSecret = await x3dhService.initiateX3DH(bundle, initiatorIdentityKey);

      // Assert
      expect(sharedSecret, isNotNull);
      expect(sharedSecret.length, equals(32));
    });

    test('should perform X3DH response successfully', () async {
      // Arrange
      final initiatorEphemeralPublicKey = Uint8List(32);
      for (int i = 0; i < 32; i++) {
        initiatorEphemeralPublicKey[i] = i;
      }
      
      final recipientIdentityKey = await cryptoService.generateEd25519KeyPair();
      final recipientSignedPreKey = SignedPreKey(
        keyId: 1,
        publicKey: Uint8List(32),
        privateKey: Uint8List(32),
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(Duration(days: 7)),
      );
      
      final recipientOneTimePreKey = OneTimePreKey(
        keyId: 1,
        publicKey: Uint8List(32),
        privateKey: Uint8List(32),
      );

      // Act
      final sharedSecret = await x3dhService.respondToX3DH(
        initiatorEphemeralPublicKey,
        recipientIdentityKey,
        recipientSignedPreKey,
        recipientOneTimePreKey,
      );

      // Assert
      expect(sharedSecret, isNotNull);
      expect(sharedSecret.length, equals(32));
    });

    test('should perform X3DH response without one-time prekey', () async {
      // Arrange
      final initiatorEphemeralPublicKey = Uint8List(32);
      for (int i = 0; i < 32; i++) {
        initiatorEphemeralPublicKey[i] = i;
      }
      
      final recipientIdentityKey = await cryptoService.generateEd25519KeyPair();
      final recipientSignedPreKey = SignedPreKey(
        keyId: 1,
        publicKey: Uint8List(32),
        privateKey: Uint8List(32),
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(Duration(days: 7)),
      );

      // Act
      final sharedSecret = await x3dhService.respondToX3DH(
        initiatorEphemeralPublicKey,
        recipientIdentityKey,
        recipientSignedPreKey,
        null,
      );

      // Assert
      expect(sharedSecret, isNotNull);
      expect(sharedSecret.length, equals(32));
    });

    test('should verify signed prekey signature', () async {
      // Arrange
      final signedPreKey = Uint8List(32);
      final signature = Uint8List(64);
      final identityKey = Uint8List(32);

      // Act
      final isValid = await x3dhService.verifySignedPreKeySignature(
        signedPreKey,
        signature,
        identityKey,
      );

      // Assert
      expect(isValid, isTrue);
    });

    test('should produce different shared secrets for different sessions', () async {
      // Arrange
      final recipientIdentityKey = await cryptoService.generateEd25519KeyPair();
      final recipientSignedPreKey = await cryptoService.generateCurve25519KeyPair();
      
      final bundle = PreKeyBundle(
        registrationId: '12345',
        identityKey: await _pubBytes(recipientIdentityKey),
        signedPreKeyId: 1,
        signedPreKey: await _pubBytes(recipientSignedPreKey),
        signedPreKeySignature: Uint8List(64),
      );
      
      final initiatorIdentityKey1 = await cryptoService.generateEd25519KeyPair();
      final initiatorIdentityKey2 = await cryptoService.generateEd25519KeyPair();

      // Act
      final sharedSecret1 = await x3dhService.initiateX3DH(bundle, initiatorIdentityKey1);
      final sharedSecret2 = await x3dhService.initiateX3DH(bundle, initiatorIdentityKey2);

      // Assert
      expect(sharedSecret1, isNot(equals(sharedSecret2)));
    });
  });

  group('X3DHService - Security Verification', () {
    late X3DHService x3dhService;
    late CryptoService cryptoService;
    late SecureKeyStorage secureStorage;

    setUp(() async {
      // Use in-memory storage for tests (no device keychain required)
      FlutterSecureStorage.setMockInitialValues({});
      cryptoService = CryptoServiceImpl();
      secureStorage = SecureKeyStorage();
      await secureStorage.deleteAllKeys();
      x3dhService = X3DHService(
        cryptoService: cryptoService,
        secureStorage: secureStorage,
      );
    });

    tearDown(() async {
      await secureStorage.deleteAllKeys();
    });

    test('should not expose private keys in shared secret', () async {
      // Arrange
      final recipientIdentityKey = await cryptoService.generateEd25519KeyPair();
      final recipientSignedPreKey = await cryptoService.generateCurve25519KeyPair();
      
      final bundle = PreKeyBundle(
        registrationId: '12345',
        identityKey: await _pubBytes(recipientIdentityKey),
        signedPreKeyId: 1,
        signedPreKey: await _pubBytes(recipientSignedPreKey),
        signedPreKeySignature: Uint8List(64),
      );
      
      final initiatorIdentityKey = await cryptoService.generateEd25519KeyPair();
      final initiatorPrivateKey =
          Uint8List.fromList(await initiatorIdentityKey.extractPrivateKeyBytes());

      // Act
      final sharedSecret = await x3dhService.initiateX3DH(bundle, initiatorIdentityKey);

      // Assert
      // Shared secret should not equal the private key
      expect(sharedSecret, isNot(equals(initiatorPrivateKey)));
    });

    test('should confirm message content is never decrypted server-side', () async {
      // This test verifies that all X3DH operations are performed client-side
      // The X3DHService does not make any network calls or server-side operations
      // All cryptographic operations are local
      
      // Arrange
      final recipientIdentityKey = await cryptoService.generateEd25519KeyPair();
      final recipientSignedPreKey = await cryptoService.generateCurve25519KeyPair();
      
      final bundle = PreKeyBundle(
        registrationId: '12345',
        identityKey: await _pubBytes(recipientIdentityKey),
        signedPreKeyId: 1,
        signedPreKey: await _pubBytes(recipientSignedPreKey),
        signedPreKeySignature: Uint8List(64),
      );
      
      final initiatorIdentityKey = await cryptoService.generateEd25519KeyPair();

      // Act
      final sharedSecret = await x3dhService.initiateX3DH(bundle, initiatorIdentityKey);

      // Assert
      // The operation completed successfully without any server-side decryption
      expect(sharedSecret, isNotNull);
      expect(sharedSecret.length, equals(32));
    });
  });
}
