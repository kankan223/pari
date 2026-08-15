import 'dart:typed_data';
import 'package:civic_commons/crypto/secure_key_storage.dart';

/// Secure storage for blind hash IDs
///
/// This service provides secure storage for blind hash IDs using
/// hardware-backed keystore (flutter_secure_storage).
///
/// Security:
/// - Blind hash IDs are stored in hardware-backed secure storage
/// - No raw phone numbers are ever stored
/// - No logging of blind hash IDs
class IdentityStorage {
  final SecureKeyStorage _secureStorage;

  // Storage key for blind hash ID
  static const String _blindHashIdKey = 'blind_hash_id';

  IdentityStorage({
    required SecureKeyStorage secureStorage,
  }) : _secureStorage = secureStorage;

  /// Store a blind hash ID
  ///
  /// Parameters:
  /// - blindHashId: The blind hash ID to store
  ///
  /// Security: Blind hash ID is stored in hardware-backed secure storage
  Future<void> storeBlindHashId(String blindHashId) async {
    final blindHashIdBytes = Uint8List.fromList(blindHashId.codeUnits);
    await _secureStorage.write(key: _blindHashIdKey, value: blindHashIdBytes);
  }

  /// Get the stored blind hash ID
  ///
  /// Returns: The stored blind hash ID, or null if not set
  ///
  /// Security: Blind hash ID is retrieved from hardware-backed secure storage
  Future<String?> getBlindHashId() async {
    final blindHashIdBytes = await _secureStorage.read(key: _blindHashIdKey);
    if (blindHashIdBytes == null) {
      return null;
    }
    return String.fromCharCodes(blindHashIdBytes);
  }

  /// Check if a blind hash ID is stored
  ///
  /// Returns: true if a blind hash ID is stored, false otherwise
  Future<bool> hasBlindHashId() async {
    final blindHashId = await getBlindHashId();
    return blindHashId != null;
  }

  /// Delete the stored blind hash ID
  ///
  /// Security: This is a destructive operation that cannot be undone
  Future<void> deleteBlindHashId() async {
    await _secureStorage.delete(key: _blindHashIdKey);
  }

  /// Update the stored blind hash ID
  ///
  /// Parameters:
  /// - blindHashId: The new blind hash ID to store
  ///
  /// Security: Blind hash ID is stored in hardware-backed secure storage
  Future<void> updateBlindHashId(String blindHashId) async {
    await storeBlindHashId(blindHashId);
  }
}
