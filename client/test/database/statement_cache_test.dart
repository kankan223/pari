import 'package:civic_commons/database/data/in_memory_statement_cache.dart';
import 'package:civic_commons/database/domain/statement_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StatementCacheConfig - Task 12.2', () {
    test('default config has sensible defaults', () {
      const config = StatementCacheConfig();
      expect(config.maxCacheSize, 50);
      expect(config.enableWalMode, isTrue);
      expect(config.pageSize, 4096);
      expect(config.journalMode, 'WAL');
      expect(config.synchronousMode, 1);
      expect(config.tempStore, 2);
    });

    test('conservative config reduces resource usage', () {
      const config = StatementCacheConfig.conservative();
      expect(config.maxCacheSize, 20);
      expect(config.mmapSize, 0);
      expect(config.cacheSizePages, -4000);
    });

    test('aggressive config increases resource usage', () {
      const config = StatementCacheConfig.aggressive();
      expect(config.maxCacheSize, 100);
      expect(config.mmapSize, 536870912);
      expect(config.cacheSizePages, -16000);
    });

    test('conservative is smaller than default', () {
      const conservative = StatementCacheConfig.conservative();
      const default_ = StatementCacheConfig();
      expect(conservative.maxCacheSize, lessThan(default_.maxCacheSize));
      expect(conservative.mmapSize, lessThan(default_.mmapSize));
    });
  });

  group('StatementCacheStats - Task 12.2', () {
    test('default stats have zero values', () {
      const stats = StatementCacheStats();
      expect(stats.hits, 0);
      expect(stats.misses, 0);
      expect(stats.evictions, 0);
      expect(stats.cachedCount, 0);
      expect(stats.maxSize, 50);
    });

    test('hitRatio computes correctly', () {
      const stats = StatementCacheStats(hits: 7, misses: 3);
      expect(stats.hitRatio, 0.7);
    });

    test('hitRatio is NaN when no requests', () {
      const stats = StatementCacheStats();
      expect(stats.hitRatio, isNaN);
    });

    test('hitRatio is 1.0 when all hits', () {
      const stats = StatementCacheStats(hits: 10, misses: 0);
      expect(stats.hitRatio, 1.0);
    });

    test('hitRatio is 0.0 when all misses', () {
      const stats = StatementCacheStats(hits: 0, misses: 10);
      expect(stats.hitRatio, 0.0);
    });

    test('copyWith creates new instance', () {
      const original = StatementCacheStats();
      final updated = original.copyWith(hits: 5, misses: 3);
      expect(updated.hits, 5);
      expect(updated.misses, 3);
      expect(original.hits, 0);
    });

    test('equality by all fields', () {
      const a = StatementCacheStats(
          hits: 1, misses: 2, evictions: 3, cachedCount: 4, maxSize: 50);
      const b = StatementCacheStats(
          hits: 1, misses: 2, evictions: 3, cachedCount: 4, maxSize: 50);
      const c = StatementCacheStats(
          hits: 1, misses: 2, evictions: 3, cachedCount: 5, maxSize: 50);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('hashCode is consistent', () {
      const a = StatementCacheStats(hits: 5);
      const b = StatementCacheStats(hits: 5);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('InMemoryStatementCache - Task 12.2', () {
    late InMemoryStatementCache cache;

    setUp(() {
      cache = InMemoryStatementCache();
    });

    test('applyConfig stores config', () async {
      const config = StatementCacheConfig(maxCacheSize: 100);
      await cache.applyConfig(config);
      expect(cache.appliedConfigs, hasLength(1));
      expect(cache.appliedConfigs.first.maxCacheSize, 100);
    });

    test('getStats returns initial zeros', () async {
      final stats = await cache.getStats();
      expect(stats.hits, 0);
      expect(stats.misses, 0);
    });

    test('clearCache sets cacheWasCleared', () async {
      expect(cache.cacheWasCleared, isFalse);
      await cache.clearCache();
      expect(cache.cacheWasCleared, isTrue);
    });

    test('optimizeQueryPlans sets optimizeWasCalled', () async {
      expect(cache.optimizeWasCalled, isFalse);
      await cache.optimizeQueryPlans();
      expect(cache.optimizeWasCalled, isTrue);
    });

    test('getPageCount returns positive value', () async {
      expect(await cache.getPageCount(), greaterThan(0));
    });

    test('getPageSize returns power of 2', () async {
      final size = await cache.getPageSize();
      expect(size, greaterThanOrEqualTo(512));
      expect(size & (size - 1), 0, reason: 'Page size must be power of 2');
    });

    test('simulateHit increments hits', () async {
      cache.simulateHit();
      cache.simulateHit();
      final stats = await cache.getStats();
      expect(stats.hits, 2);
    });

    test('simulateMiss increments misses and cachedCount', () async {
      cache.simulateMiss();
      final stats = await cache.getStats();
      expect(stats.misses, 1);
      expect(stats.cachedCount, 1);
    });

    test('simulateEviction increments evictions and decrements cachedCount',
        () async {
      cache.simulateMiss();
      cache.simulateMiss();
      cache.simulateEviction();
      final stats = await cache.getStats();
      expect(stats.evictions, 1);
      expect(stats.cachedCount, 1);
    });

    test('clearCache resets cachedCount and increments evictions', () async {
      cache.simulateMiss();
      cache.simulateMiss();
      cache.simulateMiss();
      await cache.clearCache();
      final stats = await cache.getStats();
      expect(stats.cachedCount, 0);
      expect(stats.evictions, 3);
    });

    test('multiple configs are recorded', () async {
      await cache.applyConfig(const StatementCacheConfig.conservative());
      await cache.applyConfig(const StatementCacheConfig());
      await cache.applyConfig(const StatementCacheConfig.aggressive());
      expect(cache.appliedConfigs, hasLength(3));
    });
  });
}
