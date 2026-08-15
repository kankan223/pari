import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cryptography/cryptography.dart';

/// Secure key storage wrapper using hardware-backed keystore
///
/// This class provides a secure interface for storing cryptographic keys
/// using the device's hardware-backed keystore (Keychain on iOS, Keystore on Android).
///
/// Security guarantees:
/// - Keys are never stored in plaintext
/// - Keys are never written to SQLite or SharedPreferences
/// - Keys are never logged or exposed in debug output
/// - Private keys are stored in hardware-backed secure storage when available
/// - Keys can only be accessed by this application
class SecureKeyStorage {
  final FlutterSecureStorage _secureStorage;

  // Storage keys for different key types
  static const String _identityPrivateKey = 'identity_private_key';
  static const String _identityPublicKey = 'identity_public_key';
  static const String _signedPreKeyPrivate = 'signed_prekey_private';
  static const String _signedPreKeyPublic = 'signed_prekey_public';
  static const String _oneTimePreKeyPrefix = 'one_time_prekey_';

  SecureKeyStorage({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              // Use hardware-backed keystore when available
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
              ),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  /// Generic write for arbitrary sensitive bytes (used by the identity layer).
  ///
  /// Security: Value is base64-encoded before storage in the hardware keystore.
  Future<void> write({required String key, required Uint8List value}) async {
    await _secureStorage.write(key: key, value: base64Encode(value));
  }

  /// Generic read for arbitrary sensitive bytes (used by the identity layer).
  ///
  /// Returns: The decoded bytes, or null if the key is not set.
  Future<Uint8List?> read({required String key}) async {
    final value = await _secureStorage.read(key: key);
    if (value == null) {
      return null;
    }
    return Uint8List.fromList(base64Decode(value));
  }

  /// Generic delete for arbitrary sensitive bytes (used by the identity layer).
  Future<void> delete({required String key}) async {
    await _secureStorage.delete(key: key);
  }

  /// Stores an Ed25519 identity key pair
  ///
  /// Parameters:
  /// - keyPair: The Ed25519 key pair to store
  ///
  /// Security: Private key is stored in hardware-backed secure storage.
  /// Public key is stored for sharing with other users.
  Future<void> storeIdentityKeyPair(SimpleKeyPair keyPair) async {
    // Extract private key bytes
    final privateKey =
        Uint8List.fromList(await keyPair.extractPrivateKeyBytes());
    final publicKey =
        Uint8List.fromList((await keyPair.extractPublicKey()).bytes);

    // Store private key in secure storage
    await _secureStorage.write(
      key: _identityPrivateKey,
      value: base64Encode(privateKey),
    );

    // Store public key in secure storage (can be shared)
    await _secureStorage.write(
      key: _identityPublicKey,
      value: base64Encode(publicKey),
    );

    // Securely wipe private key bytes from memory
    privateKey.fillRange(0, privateKey.length, 0);
  }

  /// Retrieves the Ed25519 identity key pair
  ///
  /// Returns: The stored Ed25519 key pair, or null if not found
  ///
  /// Security: Private key is retrieved from hardware-backed secure storage
  Future<SimpleKeyPair?> getIdentityKeyPair() async {
    // Retrieve private key
    final privateKeyBase64 =
        await _secureStorage.read(key: _identityPrivateKey);
    if (privateKeyBase64 == null) {
      return null;
    }

    // Retrieve public key
    final publicKeyBase64 = await _secureStorage.read(key: _identityPublicKey);
    if (publicKeyBase64 == null) {
      return null;
    }

    // Decode keys
    final privateKey = base64Decode(privateKeyBase64);
    final publicKey = base64Decode(publicKeyBase64);

    // Create key pair
    final keyPair = SimpleKeyPairData(
      privateKey,
      publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
      type: KeyPairType.ed25519,
    );

    // Securely wipe private key bytes from memory
    privateKey.fillRange(0, privateKey.length, 0);

    return keyPair;
  }

  /// Stores a signed prekey for Signal Protocol
  ///
  /// Parameters:
  /// - keyPair: The Curve25519 signed prekey pair
  /// - keyId: The unique identifier for this prekey
  ///
  /// Security: Private key is stored in hardware-backed secure storage
  Future<void> storeSignedPreKey(SimpleKeyPair keyPair, int keyId) async {
    // Extract private key bytes
    final privateKey =
        Uint8List.fromList(await keyPair.extractPrivateKeyBytes());
    final publicKey =
        Uint8List.fromList((await keyPair.extractPublicKey()).bytes);

    // Store private key with key ID
    await _secureStorage.write(
      key: '$_signedPreKeyPrivate$keyId',
      value: base64Encode(privateKey),
    );

    // Store public key with key ID
    await _secureStorage.write(
      key: '$_signedPreKeyPublic$keyId',
      value: base64Encode(publicKey),
    );

    // Securely wipe private key bytes from memory
    privateKey.fillRange(0, privateKey.length, 0);
  }

  /// Retrieves a signed prekey by ID
  ///
  /// Parameters:
  /// - keyId: The unique identifier for the prekey
  ///
  /// Returns: The stored Curve25519 signed prekey pair, or null if not found
  Future<SimpleKeyPair?> getSignedPreKey(int keyId) async {
    // Retrieve private key
    final privateKeyBase64 =
        await _secureStorage.read(key: '$_signedPreKeyPrivate$keyId');
    if (privateKeyBase64 == null) {
      return null;
    }

    // Retrieve public key
    final publicKeyBase64 =
        await _secureStorage.read(key: '$_signedPreKeyPublic$keyId');
    if (publicKeyBase64 == null) {
      return null;
    }

    // Decode keys
    final privateKey = base64Decode(privateKeyBase64);
    final publicKey = base64Decode(publicKeyBase64);

    // Create key pair
    final keyPair = SimpleKeyPairData(
      privateKey,
      publicKey: SimplePublicKey(publicKey, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );

    // Securely wipe private key bytes from memory
    privateKey.fillRange(0, privateKey.length, 0);

    return keyPair;
  }

  /// Stores a one-time prekey for Signal Protocol
  ///
  /// Parameters:
  /// - keyPair: The Curve25519 one-time prekey pair
  /// - keyId: The unique identifier for this prekey
  ///
  /// Security: Private key is stored in hardware-backed secure storage
  Future<void> storeOneTimePreKey(SimpleKeyPair keyPair, int keyId) async {
    // Extract private key bytes
    final privateKey =
        Uint8List.fromList(await keyPair.extractPrivateKeyBytes());

    // Store private key with key ID
    await _secureStorage.write(
      key: '$_oneTimePreKeyPrefix$keyId',
      value: base64Encode(privateKey),
    );

    // Securely wipe private key bytes from memory
    privateKey.fillRange(0, privateKey.length, 0);
  }

  /// Retrieves and removes a one-time prekey by ID
  ///
  /// Parameters:
  /// - keyId: The unique identifier for the prekey
  ///
  /// Returns: The stored Curve25519 one-time prekey pair, or null if not found
  ///
  /// Security: The prekey is deleted after retrieval (one-time use)
  Future<SimpleKeyPair?> consumeOneTimePreKey(int keyId) async {
    // Retrieve private key
    final privateKeyBase64 =
        await _secureStorage.read(key: '$_oneTimePreKeyPrefix$keyId');
    if (privateKeyBase64 == null) {
      return null;
    }

    // Decode private key
    final privateKey = base64Decode(privateKeyBase64);

    // Delete the key from storage (one-time use)
    await _secureStorage.delete(key: '$_oneTimePreKeyPrefix$keyId');

    // Derive the corresponding public key from the private key seed
    final derivedPair = await X25519().newKeyPairFromSeed(privateKey);
    final publicKey = (await derivedPair.extractPublicKey()).bytes;

    // Create key pair
    final keyPair = SimpleKeyPairData(
      privateKey,
      publicKey: SimplePublicKey(publicKey, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );

    // Securely wipe private key bytes from memory
    privateKey.fillRange(0, privateKey.length, 0);

    return keyPair;
  }

  /// Deletes all stored keys (for duress PIN or account deletion)
  ///
  /// Security: This is a destructive operation that cannot be undone
  Future<void> deleteAllKeys() async {
    await _secureStorage.deleteAll();
  }

  /// Checks if identity keys exist
  ///
  /// Returns: true if identity keys are stored, false otherwise
  Future<bool> hasIdentityKeys() async {
    final privateKey = await _secureStorage.read(key: _identityPrivateKey);
    return privateKey != null;
  }

  /// Securely wipes sensitive data from memory
  ///
  /// Parameters:
  /// - data: The sensitive data to wipe
  ///
  /// Security: Overwrites memory with zeros to prevent data leakage
  void secureWipe(Uint8List data) {
    data.fillRange(0, data.length, 0);
  }
}
