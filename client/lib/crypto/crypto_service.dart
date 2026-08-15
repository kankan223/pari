import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// Abstract interface for cryptographic operations
///
/// This service provides the foundation for all zero-knowledge encryption
/// operations in the Civic Commons application. All implementations must
/// ensure that private keys never leave the secure enclave.
abstract class CryptoService {
  /// Derives a cryptographic key from a PIN using Argon2id
  ///
  /// Parameters:
  /// - pin: The user's PIN code (6-8 digits)
  /// - salt: A cryptographic salt (must be 16 bytes)
  ///
  /// Returns: A 32-byte derived key suitable for AES-256 encryption
  ///
  /// Security: The derived key is used to encrypt the SQLCipher database.
  /// The PIN is never stored; only the derived key is used in memory.
  Future<Uint8List> deriveKeyFromPin(String pin, Uint8List salt);

  /// Encrypts plaintext data using AES-256-GCM
  ///
  /// Parameters:
  /// - plaintext: The data to encrypt
  /// - key: A 32-byte encryption key
  ///
  /// Returns: Encrypted data with authentication tag
  ///
  /// Security: Uses authenticated encryption to ensure integrity and confidentiality
  Future<Uint8List> encrypt(Uint8List plaintext, Uint8List key);

  /// Decrypts ciphertext data using AES-256-GCM
  ///
  /// Parameters:
  /// - ciphertext: The encrypted data with authentication tag
  /// - key: A 32-byte decryption key
  ///
  /// Returns: Decrypted plaintext data
  ///
  /// Security: Authentication is verified before decryption
  Future<Uint8List> decrypt(Uint8List ciphertext, Uint8List key);

  /// Generates an Ed25519 key pair for identity keys
  ///
  /// Returns: A SimpleKeyPair containing public and private keys
  ///
  /// Security: Ed25519 is used for digital signatures and identity verification.
  /// The private key must be stored in hardware-backed secure storage.
  Future<SimpleKeyPair> generateEd25519KeyPair();

  /// Generates a Curve25519 key pair for Signal Protocol prekeys
  ///
  /// Returns: A SimpleKeyPair containing public and private keys
  ///
  /// Security: Curve25519 is used for Diffie-Hellman key exchange in Signal Protocol.
  /// The private key must be stored in hardware-backed secure storage.
  Future<SimpleKeyPair> generateCurve25519KeyPair();

  /// Generates a cryptographically secure random salt
  ///
  /// Returns: A 16-byte random salt
  ///
  /// Security: Salts must be unique per user and stored alongside the encrypted data
  Uint8List generateSalt();

  /// Securely wipes sensitive data from memory
  ///
  /// Parameters:
  /// - data: The sensitive data to wipe
  ///
  /// Security: Overwrites memory with zeros to prevent data leakage
  void secureWipe(Uint8List data);
}
