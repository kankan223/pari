import 'dart:math';

/// Generates RFC 4122 version-4 UUID idempotency keys (Task 5.2).
///
/// Every queued mutation is assigned a unique transaction UUID that the sync
/// transport attaches as the `Idempotency-Key` header — the server dedupes
/// on it, so a retried (but already-processed) push never double-applies.
///
/// SECURITY CHECKPOINT (Task 5.2/5.3): keys are produced from a
/// cryptographically secure RNG (`Random.secure()`), so they are random and
/// not predictable. A deterministic [Random] may be injected for tests only.
class IdempotencyKeyGenerator {
  final Random _random;

  IdempotencyKeyGenerator({Random? random})
      : _random = random ?? Random.secure();

  /// The HTTP header name carrying the idempotency key.
  static const String headerName = 'Idempotency-Key';

  /// Generates a fresh UUID v4 string, e.g. `f47ac10b-58cc-4372-a567-0e02b2c3d479`.
  ///
  /// Version (4) and variant (RFC 4122) bits are fixed; the remaining 122
  /// bits are random.
  String generate() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xx

    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
