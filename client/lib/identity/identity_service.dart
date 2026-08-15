import 'package:civic_commons/identity/phone_validator.dart';
import 'package:civic_commons/identity/phone_hasher.dart';
import 'package:civic_commons/identity/salt_manager.dart';
import 'package:civic_commons/identity/identity_storage.dart';

/// Identity service for blind hash ID generation
///
/// This service orchestrates phone number validation, hashing, and
/// blind hash ID generation for user identity management.
///
/// Security:
/// - Never logs raw phone numbers
/// - Never persists raw phone numbers to disk
/// - All phone number bytes are securely wiped after hashing
/// - Blind hash IDs are stored securely
class IdentityService {
  final SaltManager _saltManager;
  final IdentityStorage _identityStorage;

  IdentityService({
    required PhoneValidator phoneValidator,
    required PhoneHasher phoneHasher,
    required SaltManager saltManager,
    required IdentityStorage identityStorage,
  })  : _saltManager = saltManager,
        _identityStorage = identityStorage;

  /// Generate a blind hash ID from a phone number
  ///
  /// This method validates the phone number, hashes it with the current salt,
  /// and stores the resulting blind hash ID.
  ///
  /// Parameters:
  /// - phoneNumber: The E.164 formatted phone number
  ///
  /// Returns: The blind hash ID
  ///
  /// Throws: [InvalidPhoneNumberException] if the phone number is invalid
  /// Throws: [SaltNotAvailableException] if no salt is available
  ///
  /// Security:
  /// - Phone number is validated before hashing
  /// - Phone number bytes are securely wiped after hashing
  /// - No logging of raw phone numbers
  Future<String> generateBlindHashId(String phoneNumber) async {
    // Validate phone number format
    if (!PhoneValidator.isValidE164(phoneNumber)) {
      throw InvalidPhoneNumberException('Invalid E.164 phone number format');
    }

    // Get current salt
    final currentSalt = await _saltManager.getCurrentSalt();
    if (currentSalt == null) {
      throw SaltNotAvailableException('No salt available for hashing');
    }

    // Hash phone number
    final blindHashId =
        await PhoneHasher.hashPhoneNumber(phoneNumber, currentSalt);

    // Store blind hash ID
    await _identityStorage.storeBlindHashId(blindHashId);

    return blindHashId;
  }

  /// Validate a phone number against a blind hash ID
  ///
  /// This method validates a phone number by checking if it hashes to
  /// the provided blind hash ID using the current or previous salt.
  ///
  /// Parameters:
  /// - phoneNumber: The E.164 formatted phone number
  /// - blindHashId: The blind hash ID to validate against
  ///
  /// Returns: true if the phone number hashes to the blind hash ID, false otherwise
  ///
  /// Security:
  /// - Phone number is validated before hashing
  /// - Phone number bytes are securely wiped after hashing
  /// - No logging of raw phone numbers
  Future<bool> validatePhoneNumber(
      String phoneNumber, String blindHashId) async {
    // Validate phone number format
    if (!PhoneValidator.isValidE164(phoneNumber)) {
      return false;
    }

    // Validate with fallback to previous salt
    return await _saltManager.validateHashWithFallback(
      phoneNumber,
      blindHashId,
      (phone, salt) => PhoneHasher.verifyPhoneHash(phone, salt, blindHashId),
    );
  }

  /// Get the stored blind hash ID
  ///
  /// Returns: The stored blind hash ID, or null if not set
  ///
  /// Security: Blind hash ID is retrieved from secure storage
  Future<String?> getBlindHashId() async {
    return await _identityStorage.getBlindHashId();
  }

  /// Check if a blind hash ID is already stored
  ///
  /// Returns: true if a blind hash ID is stored, false otherwise
  Future<bool> hasBlindHashId() async {
    final blindHashId = await _identityStorage.getBlindHashId();
    return blindHashId != null;
  }

  /// Delete the stored blind hash ID
  ///
  /// Security: This is a destructive operation that cannot be undone
  Future<void> deleteBlindHashId() async {
    await _identityStorage.deleteBlindHashId();
  }

  /// Initialize the identity service with a salt from the backend
  ///
  /// Parameters:
  /// - salt: The salt to use for phone number hashing
  ///
  /// Security: Salt is stored in hardware-backed secure storage
  Future<void> initialize(String salt) async {
    await _saltManager.setCurrentSalt(salt);
  }

  /// Check if salt rotation is needed
  ///
  /// Returns: true if the salt needs rotation (older than 90 days)
  Future<bool> needsSaltRotation() async {
    return await _saltManager.needsRotation();
  }

  /// Rotate the salt with a new salt from the backend
  ///
  /// Parameters:
  /// - newSalt: The new salt to use for phone number hashing
  ///
  /// Security: Old salt is kept as previous for fallback validation
  Future<void> rotateSalt(String newSalt) async {
    await _saltManager.rotateSalt(newSalt);
  }

  /// Get the salt rotation date
  ///
  /// Returns: The date when the salt was last rotated, or null if not set
  Future<DateTime?> getSaltRotationDate() async {
    return await _saltManager.getRotationDate();
  }

  /// Delete all identity data (for account deletion or duress PIN)
  ///
  /// Security: This is a destructive operation that cannot be undone
  Future<void> deleteAllIdentityData() async {
    await _identityStorage.deleteBlindHashId();
    await _saltManager.deleteAllSalts();
  }
}

/// Exception thrown when an invalid phone number is provided
class InvalidPhoneNumberException implements Exception {
  final String message;

  InvalidPhoneNumberException(this.message);

  @override
  String toString() => 'InvalidPhoneNumberException: $message';
}

/// Exception thrown when no salt is available for hashing
class SaltNotAvailableException implements Exception {
  final String message;

  SaltNotAvailableException(this.message);

  @override
  String toString() => 'SaltNotAvailableException: $message';
}
