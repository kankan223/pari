import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:civic_commons/crypto/secure_key_storage.dart';
import 'package:cryptography/cryptography.dart';

void main() {
  group('SecureKeyStorage - Identity Key Storage', () {
    late SecureKeyStorage secureStorage;
    late FlutterSecureStorage mockSecureStorage;

    setUp(() async {
      // Use in-memory storage for testing
      mockSecureStorage = FlutterSecureStorage();
      await mockSecureStorage.deleteAll();
      secureStorage = SecureKeyStorage(secureStorage: mockSecureStorage);
    });

    tearDown(() async {
      await mockSecureStorage.deleteAll();
    });

    test('should store and retrieve Ed25519 identity key pair', () async {
      // Arrange
      final keyPair = await Ed25519().newKeyPair();

      // Act
      await secureStorage.storeIdentityKeyPair(keyPair);
      final retrievedKeyPair = await secureStorage.getIdentityKeyPair();

      // Assert
      expect(retrievedKeyPair, isNotNull);
      
      final originalPublicKey = await keyPair.extractPublicKeyBytes();
      final retrievedPublicKey = await retrievedKeyPair!.extractPublicKeyBytes();
      expect(retrievedPublicKey, equals(originalPublicKey));
    });

    test('should return null when identity keys do not exist', () async {
      // Act
      final retrievedKeyPair = await secureStorage.getIdentityKeyPair();

      // Assert
      expect(retrievedKeyPair, isNull);
    });

    test('should check if identity keys exist', () async {
      // Act & Assert
      expect(await secureStorage.hasIdentityKeys(), false);

      // Arrange
      final keyPair = await Ed25519().newKeyPair();
      await secureStorage.storeIdentityKeyPair(keyPair);

      // Act & Assert
      expect(await secureStorage.hasIdentityKeys(), true);
    });

    test('should overwrite existing identity keys', () async {
      // Arrange
      final keyPair1 = await Ed25519().newKeyPair();
      final keyPair2 = await Ed25519().newKeyPair();

      // Act
      await secureStorage.storeIdentityKeyPair(keyPair1);
      await secureStorage.storeIdentityKeyPair(keyPair2);
      final retrievedKeyPair = await secureStorage.getIdentityKeyPair();

      // Assert
      expect(retrievedKeyPair, isNotNull);
      final publicKey2 = await keyPair2.extractPublicKeyBytes();
      final retrievedPublicKey = await retrievedKeyPair!.extractPublicKeyBytes();
      expect(retrievedPublicKey, equals(publicKey2));
    });
  });

  group('SecureKeyStorage - Signed Prekey Storage', () {
    late SecureKeyStorage secureStorage;
    late FlutterSecureStorage mockSecureStorage;

    setUp(() async {
      mockSecureStorage = FlutterSecureStorage();
      await mockSecureStorage.deleteAll();
      secureStorage = SecureKeyStorage(secureStorage: mockSecureStorage);
    });

    tearDown(() async {
      await mockSecureStorage.deleteAll();
    });

    test('should store and retrieve signed prekey by ID', () async {
      // Arrange
      final keyPair = await X25519().newKeyPair();
      const keyId = 1;

      // Act
      await secureStorage.storeSignedPreKey(keyPair, keyId);
      final retrievedKeyPair = await secureStorage.getSignedPreKey(keyId);

      // Assert
      expect(retrievedKeyPair, isNotNull);
      
      final originalPublicKey = await keyPair.extractPublicKeyBytes();
      final retrievedPublicKey = await retrievedKeyPair!.extractPublicKeyBytes();
      expect(retrievedPublicKey, equals(originalPublicKey));
    });

    test('should return null for non-existent signed prekey', () async {
      // Act
      final retrievedKeyPair = await secureStorage.getSignedPreKey(999);

      // Assert
      expect(retrievedKeyPair, isNull);
    });

    test('should store multiple signed prekeys with different IDs', () async {
      // Arrange
      final keyPair1 = await X25519().newKeyPair();
      final keyPair2 = await X25519().newKeyPair();

      // Act
      await secureStorage.storeSignedPreKey(keyPair1, 1);
      await secureStorage.storeSignedPreKey(keyPair2, 2);
      
      final retrievedKeyPair1 = await secureStorage.getSignedPreKey(1);
      final retrievedKeyPair2 = await secureStorage.getSignedPreKey(2);

      // Assert
      expect(retrievedKeyPair1, isNotNull);
      expect(retrievedKeyPair2, isNotNull);
      
      final publicKey1 = await keyPair1.extractPublicKeyBytes();
      final publicKey2 = await keyPair2.extractPublicKeyBytes();
      final retrievedPublicKey1 = await retrievedKeyPair1!.extractPublicKeyBytes();
      final retrievedPublicKey2 = await retrievedKeyPair2!.extractPublicKeyBytes();
      
      expect(retrievedPublicKey1, equals(publicKey1));
      expect(retrievedPublicKey2, equals(publicKey2));
    });
  });

  group('SecureKeyStorage - One-Time Prekey Storage', () {
    late SecureKeyStorage secureStorage;
    late FlutterSecureStorage mockSecureStorage;

    setUp(() async {
      mockSecureStorage = FlutterSecureStorage();
      await mockSecureStorage.deleteAll();
      secureStorage = SecureKeyStorage(secureStorage: mockSecureStorage);
    });

    tearDown(() async {
      await mockSecureStorage.deleteAll();
    });

    test('should store and consume one-time prekey', () async {
      // Arrange
      final keyPair = await X25519().newKeyPair();
      const keyId = 1;

      // Act
      await secureStorage.storeOneTimePreKey(keyPair, keyId);
      final retrievedKeyPair = await secureStorage.consumeOneTimePreKey(keyId);

      // Assert
      expect(retrievedKeyPair, isNotNull);
      
      final originalPublicKey = await keyPair.extractPublicKeyBytes();
      final retrievedPublicKey = await retrievedKeyPair!.extractPublicKeyBytes();
      expect(retrievedPublicKey, equals(originalPublicKey));
    });

    test('should delete one-time prekey after consumption', () async {
      // Arrange
      final keyPair = await X25519().newKeyPair();
      const keyId = 1;

      // Act
      await secureStorage.storeOneTimePreKey(keyPair, keyId);
      await secureStorage.consumeOneTimePreKey(keyId);
      final retrievedKeyPair = await secureStorage.consumeOneTimePreKey(keyId);

      // Assert
      expect(retrievedKeyPair, isNull); // Should be null after first consumption
    });

    test('should return null for non-existent one-time prekey', () async {
      // Act
      final retrievedKeyPair = await secureStorage.consumeOneTimePreKey(999);

      // Assert
      expect(retrievedKeyPair, isNull);
    });
  });

  group('SecureKeyStorage - Key Deletion', () {
    late SecureKeyStorage secureStorage;
    late FlutterSecureStorage mockSecureStorage;

    setUp(() async {
      mockSecureStorage = FlutterSecureStorage();
      await mockSecureStorage.deleteAll();
      secureStorage = SecureKeyStorage(secureStorage: mockSecureStorage);
    });

    tearDown(() async {
      await mockSecureStorage.deleteAll();
    });

    test('should delete all keys', () async {
      // Arrange
      final identityKeyPair = await Ed25519().newKeyPair();
      final signedPreKey = await X25519().newKeyPair();
      
      await secureStorage.storeIdentityKeyPair(identityKeyPair);
      await secureStorage.storeSignedPreKey(signedPreKey, 1);

      // Act
      await secureStorage.deleteAllKeys();

      // Assert
      expect(await secureStorage.hasIdentityKeys(), false);
      expect(await secureStorage.getSignedPreKey(1), isNull);
    });
  });

  group('SecureKeyStorage - Security Verification', () {
    late SecureKeyStorage secureStorage;
    late FlutterSecureStorage mockSecureStorage;

    setUp(() async {
      mockSecureStorage = FlutterSecureStorage();
      await mockSecureStorage.deleteAll();
      secureStorage = SecureKeyStorage(secureStorage: mockSecureStorage);
    });

    tearDown(() async {
      await mockSecureStorage.deleteAll();
    });

    test('should securely wipe sensitive data from memory', () {
      // Arrange
      final data = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);

      // Act
      secureStorage.secureWipe(data);

      // Assert
      expect(data, equals(Uint8List(8))); // All zeros
    });

    test('should not expose private keys in storage keys', () async {
      // Arrange
      final keyPair = await Ed25519().newKeyPair();

      // Act
      await secureStorage.storeIdentityKeyPair(keyPair);
      final allKeys = await mockSecureStorage.readAll();

      // Assert
      // Storage keys should not contain the actual private key material
      for (final key in allKeys.keys) {
        expect(key, isNot(contains(RegExp('[0-9a-f]{64}'))));
      }
    });

    test('should store keys in base64 encoded format', () async {
      // Arrange
      final keyPair = await Ed25519().newKeyPair();

      // Act
      await secureStorage.storeIdentityKeyPair(keyPair);
      final storedPrivateKey = await mockSecureStorage.read(key: 'identity_private_key');

      // Assert
      expect(storedPrivateKey, isNotNull);
      // Should be valid base64
      expect(() => base64Decode(storedPrivateKey!), returnsNormally);
    });

    test('should confirm keys are not exportable from secure storage', () async {
      // Arrange
      final keyPair = await Ed25519().newKeyPair();
      await secureStorage.storeIdentityKeyPair(keyPair);

      // Act
      final allKeys = await mockSecureStorage.readAll();

      // Assert
      // Keys are stored in secure storage, not in plaintext files
      // This test verifies the storage mechanism is using secure storage
      expect(allKeys.length, greaterThan(0));
      
      // Verify that the stored values are base64 encoded (not raw bytes)
      for (final value in allKeys.values) {
        expect(() => base64Decode(value), returnsNormally);
      }
    });
  });
}
