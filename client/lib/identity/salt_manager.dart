import 'dart:typed_data';
import 'package:civic_commons/crypto/secure_key_storage.dart';

/// Salt manager for phone number hashing
///
/// This service manages salt rotation on a quarterly basis and provides
/// fallback support for validating hashes created with older salts.
///
/// Security:
/// - Salts are fetched from secure backend (HashiCorp Vault)
/// - Salts are stored in hardware-backed secure storage
/// - No logging of raw salt values
class SaltManager {
  final SecureKeyStorage _secureStorage;

  // Salt rotation period: quarterly (3 months)
  static const Duration _rotationPeriod = Duration(days: 90);

  // Storage keys for salts
  static const String _currentSaltKey = 'current_phone_salt';
  static const String _previousSaltKey = 'previous_phone_salt';
  static const String _saltRotationDateKey = 'salt_rotation_date';

  SaltManager({
    required SecureKeyStorage secureStorage,
  }) : _secureStorage = secureStorage;

  /// Get the current salt for phone number hashing
  ///
  /// Returns: The current salt as a string, or null if not set
  ///
  /// Security: Salt is retrieved from hardware-backed secure storage
  Future<String?> getCurrentSalt() async {
    final saltBytes = await _secureStorage.read(key: _currentSaltKey);
    if (saltBytes == null) {
      return null;
    }
    return String.fromCharCodes(saltBytes);
  }

  /// Get the previous salt for fallback validation
  ///
  /// Returns: The previous salt as a string, or null if not set
  ///
  /// Security: Salt is retrieved from hardware-backed secure storage
  Future<String?> getPreviousSalt() async {
    final saltBytes = await _secureStorage.read(key: _previousSaltKey);
    if (saltBytes == null) {
      return null;
    }
    return String.fromCharCodes(saltBytes);
  }

  /// Get all salts for validation (current and previous)
  ///
  /// Returns: List of salts in order of preference (current first)
  ///
  /// Security: Salts are retrieved from hardware-backed secure storage
  Future<List<String>> getAllSalts() async {
    final salts = <String>[];

    final currentSalt = await getCurrentSalt();
    if (currentSalt != null) {
      salts.add(currentSalt);
    }

    final previousSalt = await getPreviousSalt();
    if (previousSalt != null) {
      salts.add(previousSalt);
    }

    return salts;
  }

  /// Set the current salt (fetched from secure backend)
  ///
  /// Parameters:
  /// - salt: The new salt to set as current
  ///
  /// Security: Salt is stored in hardware-backed secure storage
  Future<void> setCurrentSalt(String salt) async {
    final saltBytes = Uint8List.fromList(salt.codeUnits);
    await _secureStorage.write(key: _currentSaltKey, value: saltBytes);

    // Set the rotation date to now (microsecond precision so the stored
    // value round-trips exactly and is never "before" the wall-clock time
    // it was created at, which broke ms-truncated comparisons in tests).
    final rotationDateBytes = Uint8List.fromList(
      DateTime.now().microsecondsSinceEpoch.toString().codeUnits,
    );
    await _secureStorage.write(
        key: _saltRotationDateKey, value: rotationDateBytes);
  }

  /// Rotate the salt (move current to previous, set new current)
  ///
  /// Parameters:
  /// - newSalt: The new salt to set as current
  ///
  /// Security: Salts are stored in hardware-backed secure storage
  Future<void> rotateSalt(String newSalt) async {
    // Move current salt to previous
    final currentSalt = await getCurrentSalt();
    if (currentSalt != null) {
      final previousSaltBytes = Uint8List.fromList(currentSalt.codeUnits);
      await _secureStorage.write(
          key: _previousSaltKey, value: previousSaltBytes);
    }

    // Set new current salt
    await setCurrentSalt(newSalt);
  }

  /// Check if salt rotation is needed
  ///
  /// Returns: true if the salt needs rotation (older than 90 days)
  Future<bool> needsRotation() async {
    final rotationDateBytes =
        await _secureStorage.read(key: _saltRotationDateKey);
    if (rotationDateBytes == null) {
      return true; // No rotation date set, need to rotate
    }

    final rotationDateStr = String.fromCharCodes(rotationDateBytes);
    final rotationDate =
        DateTime.fromMicrosecondsSinceEpoch(int.parse(rotationDateStr));
    final now = DateTime.now();

    return now.difference(rotationDate) >= _rotationPeriod;
  }

  /// Get the salt rotation date
  ///
  /// Returns: The date when the salt was last rotated, or null if not set
  Future<DateTime?> getRotationDate() async {
    final rotationDateBytes =
        await _secureStorage.read(key: _saltRotationDateKey);
    if (rotationDateBytes == null) {
      return null;
    }

    final rotationDateStr = String.fromCharCodes(rotationDateBytes);
    return DateTime.fromMicrosecondsSinceEpoch(int.parse(rotationDateStr));
  }

  /// Get the quarter for a given date
  ///
  /// Parameters:
  /// - date: The date to get the quarter for
  ///
  /// Returns: The quarter number (1-4)
  static int getQuarter(DateTime date) {
    return ((date.month - 1) ~/ 3) + 1;
  }

  /// Get the quarter key for a given date
  ///
  /// This generates a unique key for each quarter for salt identification.
  ///
  /// Parameters:
  /// - date: The date to get the quarter key for
  ///
  /// Returns: The quarter key (e.g., "2024Q1")
  static String getQuarterKey(DateTime date) {
    final quarter = getQuarter(date);
    return '${date.year}Q$quarter';
  }

  /// Validate a hash against all available salts
  ///
  /// This method tries to validate a hash against the current salt first,
  /// then falls back to the previous salt if needed.
  ///
  /// Parameters:
  /// - phoneNumber: The E.164 formatted phone number
  /// - blindHashId: The blind hash ID to validate
  /// - verifyFunction: The function to use for verification
  ///
  /// Returns: true if the hash matches any salt, false otherwise
  ///
  /// Security: Phone number is not logged
  Future<bool> validateHashWithFallback(
    String phoneNumber,
    String blindHashId,
    Future<bool> Function(String, String) verifyFunction,
  ) async {
    final salts = await getAllSalts();

    for (final salt in salts) {
      final isValid = await verifyFunction(phoneNumber, salt);
      if (isValid) {
        return true;
      }
    }

    return false;
  }

  /// Delete all salts (for account deletion or duress PIN)
  ///
  /// Security: This is a destructive operation that cannot be undone
  Future<void> deleteAllSalts() async {
    await _secureStorage.delete(key: _currentSaltKey);
    await _secureStorage.delete(key: _previousSaltKey);
    await _secureStorage.delete(key: _saltRotationDateKey);
  }
}
