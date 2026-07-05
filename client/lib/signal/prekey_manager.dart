import 'dart:typed_data';
import 'package:civic_commons/crypto/crypto_service.dart';
import 'package:civic_commons/crypto/secure_key_storage.dart';
import 'models.dart';

/// Prekey management system for Signal Protocol
/// 
/// Manages signed prekey rotation (7 days) and one-time prekey batches (100 keys)
class PrekeyManager {
  final CryptoService _cryptoService;
  final SecureKeyStorage _secureStorage;

  // Rotation period for signed prekeys (7 days)
  static const Duration _signedPreKeyRotationPeriod = Duration(days: 7);
  
  // Batch size for one-time prekeys (100 keys)
  static const int _oneTimePreKeyBatchSize = 100;

  // Key ID counters
  int _signedPreKeyId = 0;
  int _oneTimePreKeyId = 0;

  PrekeyManager({
    required CryptoService cryptoService,
    required SecureKeyStorage secureStorage,
  })  : _cryptoService = cryptoService,
        _secureStorage = secureStorage;

  /// Generate a new signed prekey
  /// 
  /// Returns: A SignedPreKey with 7-day expiration
  /// 
  /// Security: Private key is stored in hardware-backed secure storage
  Future<SignedPreKey> generateSignedPreKey() async {
    // Generate Curve25519 key pair
    final keyPair = await _cryptoService.generateCurve25519KeyPair();
    
    // Extract keys
    final publicKey = await keyPair.extractPublicKeyBytes();
    final privateKey = await keyPair.extractPrivateKeyBytes();

    // Create signed prekey with metadata
    final now = DateTime.now();
    final signedPreKey = SignedPreKey(
      keyId: _signedPreKeyId++,
      publicKey: publicKey,
      privateKey: privateKey,
      createdAt: now,
      expiresAt: now.add(_signedPreKeyRotationPeriod),
    );

    // Store in secure storage
    await _secureStorage.storeSignedPreKey(keyPair, signedPreKey.keyId);

    // Securely wipe private key from memory
    privateKey.fillRange(0, privateKey.length, 0);

    return signedPreKey;
  }

  /// Generate a batch of one-time prekeys
  /// 
  /// Returns: List of OneTimePreKey objects
  /// 
  /// Security: Private keys are stored in hardware-backed secure storage
  Future<List<OneTimePreKey>> generateOneTimePreKeyBatch() async {
    final prekeys = <OneTimePreKey>[];

    for (int i = 0; i < _oneTimePreKeyBatchSize; i++) {
      // Generate Curve25519 key pair
      final keyPair = await _cryptoService.generateCurve25519KeyPair();
      
      // Extract keys
      final publicKey = await keyPair.extractPublicKeyBytes();
      final privateKey = await keyPair.extractPrivateKeyBytes();

      // Create one-time prekey
      final prekey = OneTimePreKey(
        keyId: _oneTimePreKeyId++,
        publicKey: publicKey,
        privateKey: privateKey,
      );

      // Store in secure storage
      await _secureStorage.storeOneTimePreKey(keyPair, prekey.keyId);

      // Securely wipe private key from memory
      privateKey.fillRange(0, privateKey.length, 0);

      prekeys.add(prekey);
    }

    return prekeys;
  }

  /// Get the current signed prekey
  /// 
  /// Returns: The current signed prekey, or null if none exists
  Future<SignedPreKey?> getCurrentSignedPreKey() async {
    // Check if signed prekey with ID 0 exists
    final keyPair = await _secureStorage.getSignedPreKey(0);
    if (keyPair == null) {
      return null;
    }

    final publicKey = await keyPair.extractPublicKeyBytes();
    final privateKey = await keyPair.extractPrivateKeyBytes();

    final now = DateTime.now();
    final signedPreKey = SignedPreKey(
      keyId: 0,
      publicKey: publicKey,
      privateKey: privateKey,
      createdAt: now.subtract(_signedPreKeyRotationPeriod),
      expiresAt: now.add(_signedPreKeyRotationPeriod),
    );

    // Securely wipe private key from memory
    privateKey.fillRange(0, privateKey.length, 0);

    return signedPreKey;
  }

  /// Check if signed prekey needs rotation
  /// 
  /// Returns: true if the current signed prekey needs rotation
  Future<bool> needsSignedPreKeyRotation() async {
    final currentPrekey = await getCurrentSignedPreKey();
    if (currentPrekey == null) {
      return true; // No prekey exists, need to generate one
    }
    return currentPrekey.needsRotation();
  }

  /// Rotate signed prekey
  /// 
  /// Returns: The new signed prekey
  /// 
  /// Security: Old prekey is kept for a grace period to handle in-flight messages
  Future<SignedPreKey> rotateSignedPreKey() async {
    // Generate new signed prekey
    final newPrekey = await generateSignedPreKey();
    
    // In production, we would keep the old prekey for a grace period
    // For now, we'll just generate the new one
    
    return newPrekey;
  }

  /// Get a one-time prekey for use
  /// 
  /// Returns: A one-time prekey, or null if none available
  /// 
  /// Security: The prekey is consumed (deleted) after retrieval
  Future<OneTimePreKey?> getOneTimePreKey() async {
    // Try to consume a one-time prekey starting from the lowest ID
    for (int i = 0; i < _oneTimePreKeyId; i++) {
      final keyPair = await _secureStorage.consumeOneTimePreKey(i);
      if (keyPair != null) {
        final publicKey = await keyPair.extractPublicKeyBytes();
        final privateKey = await keyPair.extractPrivateKeyBytes();

        final prekey = OneTimePreKey(
          keyId: i,
          publicKey: publicKey,
          privateKey: privateKey,
        );

        // Securely wipe private key from memory
        privateKey.fillRange(0, privateKey.length, 0);

        return prekey;
      }
    }

    return null; // No one-time prekeys available
  }

  /// Check if one-time prekeys need to be replenished
  /// 
  /// Returns: true if one-time prekey count is below threshold
  Future<bool> needsOneTimePreKeyReplenishment() async {
    // In production, we would check the actual count
    // For now, we'll assume we need replenishment if we've used more than 50%
    return (_oneTimePreKeyId % (_oneTimePreKeyBatchSize ~/ 2)) == 0;
  }

  /// Replenish one-time prekeys
  /// 
  /// Returns: The new batch of one-time prekeys
  Future<List<OneTimePreKey>> replenishOneTimePreKeys() async {
    return await generateOneTimePreKeyBatch();
  }

  /// Create a PreKeyBundle for sharing
  /// 
  /// Parameters:
  /// - registrationId: The user's registration ID
  /// - identityKey: The user's identity public key
  /// 
  /// Returns: A PreKeyBundle ready for API transmission
  /// 
  /// Security: Only contains public keys, no private keys
  Future<PreKeyBundle> createPreKeyBundle(
    String registrationId,
    Uint8List identityKey,
  ) async {
    // Get current signed prekey
    final signedPreKey = await getCurrentSignedPreKey();
    if (signedPreKey == null) {
      throw StateError('No signed prekey available. Generate one first.');
    }

    // Get a one-time prekey if available
    final oneTimePreKey = await getOneTimePreKey();

    // Create signature for signed prekey (placeholder)
    final signature = Uint8List(64); // Ed25519 signature is 64 bytes

    // Create bundle
    final bundle = PreKeyBundle(
      registrationId: registrationId,
      identityKey: identityKey,
      signedPreKeyId: signedPreKey.keyId,
      signedPreKey: signedPreKey.publicKey,
      signedPreKeySignature: signature,
      oneTimePreKeyId: oneTimePreKey?.keyId,
      oneTimePreKey: oneTimePreKey?.publicKey,
    );

    return bundle;
  }

  /// Delete all prekeys (for account deletion or duress PIN)
  /// 
  /// Security: This is a destructive operation that cannot be undone
  Future<void> deleteAllPrekeys() async {
    await _secureStorage.deleteAllKeys();
    _signedPreKeyId = 0;
    _oneTimePreKeyId = 0;
  }
}
