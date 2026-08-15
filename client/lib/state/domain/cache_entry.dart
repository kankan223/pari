import 'dart:convert';

/// A timestamped cache entry used for TTL-based cache invalidation
/// (Task 3.6 — karma cache).
///
/// Encoded as a compact JSON string (`{"v": ..., "t": <epoch µs>}`) so it can
/// live inside a [NonSensitiveStore] value slot.
class CacheEntry {
  final String value;
  final DateTime storedAt;

  const CacheEntry({required this.value, required this.storedAt});

  /// Whether this entry has aged past [ttl] as of [now].
  bool isExpiredAt(DateTime now, Duration ttl) =>
      TtlPolicy.isExpired(storedAt: storedAt, now: now, ttl: ttl);

  String encode() =>
      jsonEncode({'v': value, 't': storedAt.microsecondsSinceEpoch});

  /// Parses [raw]; returns null for malformed input (never throws).
  static CacheEntry? decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final v = decoded['v'];
      final t = decoded['t'];
      if (v is! String || t is! int) {
        return null;
      }
      // Encode stores epoch microseconds (timezone-independent); decode as
      // UTC so the round-trip is exact regardless of the machine's timezone
      // (DateTime.== compares both the instant and the isUtc flag).
      return CacheEntry(
        value: v,
        storedAt: DateTime.fromMicrosecondsSinceEpoch(t, isUtc: true),
      );
    } on FormatException {
      return null;
    } on ArgumentError {
      // Out-of-range timestamp from corrupt data — treat as absent.
      return null;
    }
  }
}

/// Pure time-to-live calculation (Task 3.6) — no dependencies, unit-tested
/// directly so the 5-minute karma invalidation is provable in isolation.
abstract final class TtlPolicy {
  /// An entry stored at [storedAt] is expired as of [now] when it has been
  /// alive for at least [ttl] (boundary-inclusive: exactly `ttl` ⇒ expired).
  static bool isExpired({
    required DateTime storedAt,
    required DateTime now,
    required Duration ttl,
  }) =>
      now.difference(storedAt) >= ttl;
}
