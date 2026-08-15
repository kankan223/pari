/// Karma score cache with a fixed 5-minute TTL (Task 3.6).
///
/// Karma scores are PUBLIC, non-sensitive data — they are cached in the
/// `karma_cache` Hive box, which is intentionally unencrypted (see
/// [HiveBoxRegistry]). The cache must never store PII, hashes, or any
/// sensitive material — the [NonSensitiveGuard] on the backing store enforces
/// this (defense-in-depth).
///
/// Expired entries are treated as absent AND removed on read (lazy
/// invalidation), so a stale score can never surface past its TTL.
abstract class KarmaCache {
  /// Karma scores are cached for exactly 5 minutes (master plan Task 3.6).
  static const Duration ttl = Duration(minutes: 5);

  /// Reads the cached karma score for [key], or null when absent or expired.
  Future<String?> readKarma(String key);

  /// Caches [value] for [key] stamped with the current time.
  Future<void> writeKarma(String key, String value);

  /// Whether a non-expired cached value exists for [key].
  Future<bool> isFresh(String key);

  /// Removes the cached value for [key].
  Future<void> invalidate(String key);

  /// Removes every cached karma value.
  Future<void> invalidateAll();
}
