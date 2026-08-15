/// Thrown when [NonSensitiveGuard] rejects a payload that looks sensitive.
class SensitivePayloadException implements Exception {
  final String reason;

  const SensitivePayloadException(this.reason);

  @override
  String toString() => 'SensitivePayloadException: $reason';
}

/// Defense-in-depth guard for [NonSensitiveStore] implementations (Task 3.5).
///
/// The PRIMARY enforcement is architectural: sensitive data (ciphertext,
/// hashes, keys, PINs) lives only inside the encrypted SQLCipher database and
/// the keychain and never reaches this store by design. This guard is a
/// secondary net — it fails loudly if a wiring mistake ever tries to persist
/// something that looks like sensitive material into a plaintext Hive box.
abstract final class NonSensitiveGuard {
  static const List<String> _sensitiveKeyMarkers = [
    'cipher',
    'hash',
    'pin',
    'phone',
    'payload',
    'session',
    'secret',
    'private',
    'token',
    'salt',
  ];

  static const List<String> _sensitiveValueMarkers = [
    '-----begin',
    'argon2',
    '{"iv":',
    '"ciphertext"',
    '"salt"',
    '"payload"',
  ];

  /// E.164 phone numbers (Task 3.6 checkpoint: PII must never reach a box).
  static final RegExp _e164Phone = RegExp(r'\+[1-9]\d{1,14}');

  /// Throws [SensitivePayloadException] when [key] or [value] matches a known
  /// sensitive marker, contains PII (E.164 phone), or looks like an encoded
  /// sensitive blob.
  static void assertNonSensitive(String key, String value) {
    final loweredKey = key.toLowerCase();
    for (final marker in _sensitiveKeyMarkers) {
      if (loweredKey.contains(marker)) {
        throw SensitivePayloadException(
          'key "$key" matches sensitive marker "$marker" — sensitive data '
          'must never be written to the non-sensitive store',
        );
      }
    }

    final loweredValue = value.toLowerCase();
    for (final marker in _sensitiveValueMarkers) {
      if (loweredValue.contains(marker)) {
        throw SensitivePayloadException(
          'value for "$key" matches sensitive marker "$marker"',
        );
      }
    }

    // E.164 phone numbers are PII — refuse them anywhere in the value
    // (mirrors the Task 2.7 redactor's phone patterns).
    if (_e164Phone.hasMatch(value)) {
      throw SensitivePayloadException(
        'value for "$key" contains an E.164 phone number (PII)',
      );
    }

    // Ciphertext and blind hashes are encoded as long base64/hex blobs in
    // this app — reject anything that looks like one.
    final looksEncoded =
        RegExp(r'^(?:[A-Za-z0-9+/]{100,}={0,2}|[0-9a-fA-F]{100,})$');
    if (looksEncoded.hasMatch(value)) {
      throw SensitivePayloadException(
        'value for "$key" looks like an encoded sensitive blob',
      );
    }
  }
}
