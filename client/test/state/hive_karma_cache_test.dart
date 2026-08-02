import 'package:civic_commons/state/data/hive_karma_cache.dart';
import 'package:civic_commons/state/data/memory_non_sensitive_store.dart';
import 'package:civic_commons/state/domain/karma_cache.dart';
import 'package:civic_commons/state/domain/non_sensitive_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HiveKarmaCache - TTL invalidation with scripted clock (Task 3.6)', () {
    late MemoryNonSensitiveStore store;
    late DateTime now;
    late HiveKarmaCache cache;

    setUp(() {
      store = MemoryNonSensitiveStore();
      now = DateTime.utc(2026, 8, 2, 12, 0, 0);
      cache = HiveKarmaCache(store: store, now: () => now);
    });

    test('write then immediate read returns the cached score', () async {
      await cache.writeKarma('peer_1', '42');
      expect(await cache.readKarma('peer_1'), '42');
      expect(await cache.isFresh('peer_1'), isTrue);
    });

    test('4:59 old score is still fresh', () async {
      await cache.writeKarma('peer_1', '42');
      now = now.add(const Duration(minutes: 4, seconds: 59));
      expect(await cache.readKarma('peer_1'), '42');
      expect(await cache.isFresh('peer_1'), isTrue);
    });

    test('exactly 5 minutes old is EXPIRED and lazily removed', () async {
      await cache.writeKarma('peer_1', '42');
      now = now.add(KarmaCache.ttl);

      expect(await cache.readKarma('peer_1'), isNull);
      expect(await cache.isFresh('peer_1'), isFalse);
      // Lazy invalidation removed the entry from the backing store.
      expect(await store.read('karma.peer_1'), isNull);
    });

    test('expired entry never surfaces even if re-read', () async {
      await cache.writeKarma('peer_1', '42');
      now = now.add(const Duration(hours: 2));
      expect(await cache.readKarma('peer_1'), isNull);
      expect(await cache.readKarma('peer_1'), isNull);
    });

    test('distinct peers are cached independently', () async {
      await cache.writeKarma('peer_1', '10');
      await cache.writeKarma('peer_2', '99');
      expect(await cache.readKarma('peer_1'), '10');
      expect(await cache.readKarma('peer_2'), '99');
    });

    test('writeKarma overwrites an existing entry with a fresh timestamp',
        () async {
      await cache.writeKarma('peer_1', '10');
      now = now.add(const Duration(minutes: 3));
      await cache.writeKarma('peer_1', '20');
      now = now.add(const Duration(minutes: 3));
      // 6 minutes after first write, 3 after second — the second is fresh.
      expect(await cache.readKarma('peer_1'), '20');
    });

    test('invalidate removes only the given key', () async {
      await cache.writeKarma('peer_1', '10');
      await cache.writeKarma('peer_2', '99');

      await cache.invalidate('peer_1');
      expect(await cache.readKarma('peer_1'), isNull);
      expect(await cache.readKarma('peer_2'), '99');
    });

    test('invalidateAll clears every cached score', () async {
      await cache.writeKarma('peer_1', '10');
      await cache.writeKarma('peer_2', '99');

      await cache.invalidateAll();
      expect(await cache.readKarma('peer_1'), isNull);
      expect(await cache.readKarma('peer_2'), isNull);
    });

    test('missing key reads null and is not fresh', () async {
      expect(await cache.readKarma('nobody'), isNull);
      expect(await cache.isFresh('nobody'), isFalse);
    });

    test('SECURITY CHECKPOINT: sensitive keys are refused by the guard',
        () async {
      await expectLater(
        cache.writeKarma('peer_hash_1', '10'),
        throwsA(isA<SensitivePayloadException>()),
      );
      expect(await cache.readKarma('peer_hash_1'), isNull);
    });
  });
}
