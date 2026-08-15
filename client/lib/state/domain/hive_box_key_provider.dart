import 'dart:typed_data';

/// Supplies 32-byte AES-256 keys for SENSITIVE Hive boxes (Task 3.6).
///
/// SECURITY MODEL: the three canonical boxes (ledger_drafts,
/// academy_progress, karma_cache) are NON-SENSITIVE and are opened WITHOUT
/// encryption. Any box opened through [HiveBoxRegistry.openSensitiveBox]
/// requires a key from this provider and is encrypted with a [HiveAesCipher]
/// at rest — so no PII or sensitive data ever sits in an unencrypted box.
abstract class HiveBoxKeyProvider {
  /// Returns the 32-byte key for [boxName], or null when the box is not
  /// registered as sensitive.
  Future<Uint8List?> keyFor(String boxName);
}
