import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'crypto_service.dart';

/// Concrete implementation of CryptoService
///
/// This implementation provides zero-knowledge cryptographic operations
/// with hardware-backed security where available.
class CryptoServiceImpl implements CryptoService {
  // Argon2id parameters as specified in MASTER_PLAN.md
  static const int _argon2Memory = 64 * 1024; // 64MB in KB
  static const int _argon2Iterations = 3;
  static const int _argon2Parallelism = 4;
  static const int _argon2HashLength = 32; // 256-bit key
  static const int _saltLength = 16; // 128-bit salt

  // AES-256-GCM algorithm
  static final AesGcm _aesGcm = AesGcm.with256bits();

  @override
  Future<Uint8List> deriveKeyFromPin(String pin, Uint8List salt) async {
    // Validate inputs
    if (pin.isEmpty) {
      throw ArgumentError('PIN cannot be empty');
    }
    if (salt.length != _saltLength) {
      throw ArgumentError('Salt must be $_saltLength bytes');
    }

    // Convert PIN to bytes
    final pinBytes = utf8.encode(pin);

    try {
      // Derive key using Argon2id (RFC 9106)
      final algorithm = Argon2id(
        memory: _argon2Memory,
        iterations: _argon2Iterations,
        parallelism: _argon2Parallelism,
        hashLength: _argon2HashLength,
      );

      final secretKey = await algorithm.deriveKey(
        secretKey: SecretKey(pinBytes),
        nonce: salt,
      );

      final derivedKey = Uint8List.fromList(await secretKey.extractBytes());

      return derivedKey;
    } finally {
      // Securely wipe PIN bytes from memory
      pinBytes.fillRange(0, pinBytes.length, 0);
    }
  }

  @override
  Future<Uint8List> encrypt(Uint8List plaintext, Uint8List key) async {
    // Validate inputs
    if (plaintext.isEmpty) {
      throw ArgumentError('Plaintext cannot be empty');
    }
    if (key.length != 32) {
      throw ArgumentError('Key must be 32 bytes for AES-256');
    }

    // Generate random nonce for GCM
    final nonce = _aesGcm.newNonce();

    // Encrypt using AES-256-GCM
    final secretBox = await _aesGcm.encrypt(
      plaintext,
      secretKey: SecretKey(key),
      nonce: nonce,
    );

    // Return concatenated nonce + ciphertext + mac
    final result = Uint8List(nonce.length +
        secretBox.cipherText.length +
        secretBox.mac.bytes.length);
    result.setAll(0, nonce);
    result.setAll(nonce.length, secretBox.cipherText);
    result.setAll(
        nonce.length + secretBox.cipherText.length, secretBox.mac.bytes);

    return result;
  }

  @override
  Future<Uint8List> decrypt(Uint8List ciphertext, Uint8List key) async {
    // Validate inputs
    if (ciphertext.isEmpty) {
      throw ArgumentError('Ciphertext cannot be empty');
    }
    if (key.length != 32) {
      throw ArgumentError('Key must be 32 bytes for AES-256');
    }

    // Extract nonce, ciphertext, and MAC
    final nonce = ciphertext.sublist(0, _aesGcm.nonceLength);
    final cipherBytes = ciphertext.sublist(
      _aesGcm.nonceLength,
      ciphertext.length - _aesGcm.macAlgorithm.macLength,
    );
    final macBytes =
        ciphertext.sublist(ciphertext.length - _aesGcm.macAlgorithm.macLength);

    // Create SecretBox
    final secretBox = SecretBox(
      cipherBytes,
      nonce: nonce,
      mac: Mac(macBytes),
    );

    // Decrypt using AES-256-GCM
    final plaintext = await _aesGcm.decrypt(
      secretBox,
      secretKey: SecretKey(key),
    );

    return Uint8List.fromList(plaintext);
  }

  @override
  Future<SimpleKeyPair> generateEd25519KeyPair() async {
    // Generate Ed25519 key pair for signatures
    final keyPair = await Ed25519().newKeyPair();
    return keyPair;
  }

  @override
  Future<SimpleKeyPair> generateCurve25519KeyPair() async {
    // Generate Curve25519 key pair for Diffie-Hellman
    final keyPair = await X25519().newKeyPair();
    return keyPair;
  }

  @override
  Uint8List generateSalt() {
    // Generate cryptographically secure random salt
    final salt = Uint8List(_saltLength);
    final random = Random.secure();
    for (int i = 0; i < _saltLength; i++) {
      salt[i] = random.nextInt(256);
    }
    return salt;
  }

  @override
  void secureWipe(Uint8List data) {
    // Overwrite memory with zeros
    data.fillRange(0, data.length, 0);
  }
}
