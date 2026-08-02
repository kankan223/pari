import 'package:civic_commons/state/domain/cache_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TtlPolicy - cache invalidation TTL logic (Task 3.6)', () {
    final storedAt = DateTime.utc(2026, 8, 2, 12, 0, 0);
    final ttl = const Duration(minutes: 5);

    test('fresh entries (younger than TTL) are NOT expired', () {
      expect(
        TtlPolicy.isExpired(
          storedAt: storedAt,
          now: storedAt.add(const Duration(minutes: 4, seconds: 59)),
          ttl: ttl,
        ),
        isFalse,
      );
      expect(
        TtlPolicy.isExpired(
          storedAt: storedAt,
          now: storedAt.add(const Duration(seconds: 1)),
          ttl: ttl,
        ),
        isFalse,
      );
    });

    test('exactly TTL old is EXPIRED (boundary-inclusive)', () {
      expect(
        TtlPolicy.isExpired(
          storedAt: storedAt,
          now: storedAt.add(const Duration(minutes: 5)),
          ttl: ttl,
        ),
        isTrue,
      );
    });

    test('older than TTL is EXPIRED', () {
      expect(
        TtlPolicy.isExpired(
          storedAt: storedAt,
          now: storedAt.add(const Duration(minutes: 5, seconds: 1)),
          ttl: ttl,
        ),
        isTrue,
      );
      expect(
        TtlPolicy.isExpired(
          storedAt: storedAt,
          now: storedAt.add(const Duration(hours: 1)),
          ttl: ttl,
        ),
        isTrue,
      );
    });

    test('zero / negative TTL expires everything immediately', () {
      expect(
        TtlPolicy.isExpired(
          storedAt: storedAt,
          now: storedAt,
          ttl: Duration.zero,
        ),
        isTrue,
      );
    });
  });

  group('CacheEntry - encoding (Task 3.6)', () {
    test('encode/decode round-trips value and timestamp', () {
      final storedAt = DateTime.utc(2026, 8, 2, 12, 0, 0, 123, 456);
      final entry = CacheEntry(value: '42', storedAt: storedAt);

      final decoded = CacheEntry.decode(entry.encode());

      expect(decoded, isNotNull);
      expect(decoded!.value, '42');
      expect(decoded.storedAt, storedAt);
    });

    test('decode returns null for malformed input (never throws)', () {
      expect(CacheEntry.decode('not json'), isNull);
      expect(CacheEntry.decode('{"v":42,"t":123}'), isNull);
      expect(CacheEntry.decode('{"v":"x"}'), isNull);
      expect(CacheEntry.decode('[]'), isNull);
      expect(CacheEntry.decode(''), isNull);
    });

    test('isExpiredAt delegates to TtlPolicy', () {
      final storedAt = DateTime.utc(2026, 8, 2, 12, 0, 0);
      final entry = CacheEntry(value: '42', storedAt: storedAt);

      expect(
        entry.isExpiredAt(
          storedAt.add(const Duration(minutes: 5)),
          const Duration(minutes: 5),
        ),
        isTrue,
      );
    });
  });
}
