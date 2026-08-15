import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Phone number hasher using Argon2id
///
/// This service hashes phone numbers using Argon2id with a salt
/// to create deterministic blind hash IDs.
///
/// Argon2id parameters (RFC 9106):
/// - memory: 65536 KiB (64 MB)
/// - iterations: 3
/// - parallelism: 4
/// - hash length: 32 bytes (256-bit)
/// - version: 19 (0x13)
///
/// Security:
/// - Never logs raw phone numbers
/// - Never persists raw phone numbers to disk
/// - Securely wipes phone number bytes after hashing
class PhoneHasher {
  // Argon2id parameters for phone number hashing
  static const int _hashLength = 32; // 256-bit hash
  static const int _memory = 64 * 1024; // 64MB (in KiB blocks)
  static const int _iterations = 3;
  static const int _parallelism = 4;

  /// Hash a phone number using Argon2id with the provided salt
  ///
  /// Parameters:
  /// - phoneNumber: The E.164 formatted phone number
  /// - salt: The salt to use for hashing (fetched from secure backend)
  ///
  /// Returns: The blind hash ID as a hex string
  ///
  /// Security:
  /// - Phone number is converted to bytes and wiped after hashing
  /// - No logging of raw phone numbers
  /// - Deterministic output for same input
  static Future<String> hashPhoneNumber(String phoneNumber, String salt) async {
    return hashPhoneNumberWithSaltBytes(
      phoneNumber,
      Uint8List.fromList(utf8.encode(salt)),
    );
  }

  /// Hash a phone number using Argon2id with the provided salt (bytes)
  ///
  /// Parameters:
  /// - phoneNumber: The E.164 formatted phone number
  /// - saltBytes: The salt bytes to use for hashing
  ///
  /// Returns: The blind hash ID as a hex string
  ///
  /// Security:
  /// - Phone number is converted to bytes and wiped after hashing
  /// - No logging of raw phone numbers
  static Future<String> hashPhoneNumberWithSaltBytes(
    String phoneNumber,
    Uint8List saltBytes,
  ) async {
    // Convert phone number to bytes
    final phoneBytes = utf8.encode(phoneNumber);

    try {
      // Perform Argon2id key derivation (RFC 9106)
      final algorithm = Argon2id(
        memory: _memory,
        iterations: _iterations,
        parallelism: _parallelism,
        hashLength: _hashLength,
      );

      final secretKey = await algorithm.deriveKey(
        secretKey: SecretKey(phoneBytes),
        nonce: saltBytes,
      );

      final hashBytes = await secretKey.extractBytes();

      // Convert hash to hex string
      final hashHex =
          hashBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      return hashHex;
    } finally {
      // Securely wipe phone number bytes from memory
      phoneBytes.fillRange(0, phoneBytes.length, 0);
    }
  }

  /// Verify a phone number hash against a blind hash ID
  ///
  /// Parameters:
  /// - phoneNumber: The E.164 formatted phone number
  /// - salt: The salt used for hashing
  /// - blindHashId: The blind hash ID to verify against
  ///
  /// Returns: true if the hash matches, false otherwise
  ///
  /// Security:
  /// - Phone number is converted to bytes and wiped after hashing
  /// - No logging of raw phone numbers
  static Future<bool> verifyPhoneHash(
    String phoneNumber,
    String salt,
    String blindHashId,
  ) async {
    final computedHash = await hashPhoneNumber(phoneNumber, salt);
    return computedHash == blindHashId;
  }

  /// Verify a phone number hash against a blind hash ID with salt bytes
  ///
  /// Parameters:
  /// - phoneNumber: The E.164 formatted phone number
  /// - saltBytes: The salt bytes used for hashing
  /// - blindHashId: The blind hash ID to verify against
  ///
  /// Returns: true if the hash matches, false otherwise
  ///
  /// Security:
  /// - Phone number is converted to bytes and wiped after hashing
  static Future<bool> verifyPhoneHashWithSaltBytes(
    String phoneNumber,
    Uint8List saltBytes,
    String blindHashId,
  ) async {
    final computedHash =
        await hashPhoneNumberWithSaltBytes(phoneNumber, saltBytes);
    return computedHash == blindHashId;
  }

  /// Get the Argon2id parameters used for hashing
  ///
  /// Returns: A map of parameter names and values
  ///
  /// Security: This is safe to log as it contains configuration only
  static Map<String, int> getParameters() {
    return {
      'hashLength': _hashLength,
      'memory': _memory,
      'iterations': _iterations,
      'parallelism': _parallelism,
    };
  }
}
