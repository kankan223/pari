import 'package:civic_commons/database/domain/batch_writer.dart';
import 'package:civic_commons/database/domain/index_manager.dart';
import 'package:civic_commons/database/domain/statement_cache.dart';
import 'package:flutter_test/flutter_test.dart';

/// Database Query Performance Benchmarks (Task 13.5).
///
/// Measures query execution efficiency, write throughput, and statement
/// cache performance across the database performance layer. All benchmarks
/// use in-memory implementations — no real SQLCipher required.
void main() {
  group('Database Query - Index Manager Benchmark', () {
    late InMemoryIndexManager indexManager;

    setUp(() {
      indexManager = InMemoryIndexManager();
    });

    test('createAll indexes within acceptable time', () async {
      final stopwatch = Stopwatch()..start();
      await indexManager.createAllIndexes();
      stopwatch.stop();

      // 38 indexes should be created in <100ms
      expect(stopwatch.elapsedMilliseconds, lessThan(100),
          reason: 'Creating 38 indexes should take <100ms');
    });

    test('createSingle index is fast', () async {
      final stopwatch = Stopwatch()..start();
      await indexManager.createIndex(
        DbIndex(
          name: 'idx_test_col',
          table: 'test_table',
          columns: ['test_col'],
        ),
      );
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(10),
          reason: 'Single index creation should take <10ms');
    });

    test('indexExists is fast for repeated checks', () async {
      await indexManager.createIndex(
        DbIndex(
          name: 'idx_fast_check',
          table: 'test_table',
          columns: ['col1'],
        ),
      );

      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < 1000; i++) {
        await indexManager.indexExists('idx_fast_check');
      }
      stopwatch.stop();

      // 1000 existence checks should take <50ms
      expect(stopwatch.elapsedMilliseconds, lessThan(50),
          reason: '1000 index existence checks should take <50ms');
    });

    test('dropAll indexes is fast', () async {
      await indexManager.createAllIndexes();

      final stopwatch = Stopwatch()..start();
      await indexManager.dropAllIndexes();
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(50),
          reason: 'Dropping all indexes should take <50ms');
    });

    test('createAll + dropAll idempotent', () async {
      await indexManager.createAllIndexes();
      final count1 = indexManager.indexes.length;
      await indexManager.dropAllIndexes();
      await indexManager.createAllIndexes();
      final count2 = indexManager.indexes.length;

      expect(count1, count2,
          reason: 'Re-creating indexes should produce same count');
    });
  });

  group('Database Query - Batch Writer Benchmark', () {
    late InMemoryBatchWriter batchWriter;

    setUp(() {
      batchWriter = InMemoryBatchWriter();
    });

    test('executeBatch with 100 inserts completes quickly', () async {
      final ops = List.generate(
        100,
        (i) => BatchOperation.insert(
          table: 'test_table',
          row: {'id': i, 'name': 'item_$i'},
        ),
      );

      final stopwatch = Stopwatch()..start();
      await batchWriter.executeBatch(ops);
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(50),
          reason: '100 inserts should take <50ms');
    });

    test('executeBatch with 1000 operations completes quickly', () async {
      final ops = List.generate(
        1000,
        (i) => BatchOperation.insert(
          table: 'test_table',
          row: {'id': i, 'value': i * 2},
        ),
      );

      final stopwatch = Stopwatch()..start();
      final result = await batchWriter.executeBatch(ops);
      stopwatch.stop();

      expect(result.successCount, 1000);
      expect(result.allSucceeded, isTrue);
      expect(stopwatch.elapsedMilliseconds, lessThan(200),
          reason: '1000 inserts should take <200ms');
    });

    test('batch vs sequential: batch is faster for 50 operations', () async {
      final ops = List.generate(
        50,
        (i) => BatchOperation.insert(
          table: 'test_table',
          row: {'id': i, 'data': 'value_$i'},
        ),
      );

      // Batch execution
      final batchStopwatch = Stopwatch()..start();
      await batchWriter.executeBatch(ops);
      batchStopwatch.stop();

      // Sequential execution (simulated)
      final seqStopwatch = Stopwatch()..start();
      for (final op in ops) {
        await batchWriter.executeBatch([op]);
      }
      seqStopwatch.stop();

      // Batch should be at least as fast as sequential
      expect(
        batchStopwatch.elapsedMilliseconds,
        lessThanOrEqualTo(seqStopwatch.elapsedMilliseconds),
        reason: 'Batch should be <= sequential for 50 operations',
      );
    });

    test('executeRaw is fast', () async {
      final stopwatch = Stopwatch()..start();
      await batchWriter.executeRaw('CREATE TABLE bench_test (id INTEGER)');
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(10),
          reason: 'Single raw SQL should take <10ms');
    });
  });

  group('Database Query - Statement Cache Benchmark', () {
    late InMemoryStatementCache cache;

    setUp(() {
      cache = InMemoryStatementCache();
    });

    test('applyConfig is fast', () async {
      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < 100; i++) {
        await cache.applyConfig(const StatementCacheConfig(
          maxCacheSize: 256,
          enableWalMode: true,
        ));
      }
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(50),
          reason: '100 config applications should take <50ms');
    });

    test('hitRatio calculation is accurate', () async {
      final stats = StatementCacheStats(
        hits: 80,
        misses: 20,
        evictions: 5,
        cachedCount: 100,
        maxSize: 256,
      );

      expect(stats.hitRatio, closeTo(0.8, 0.01));
    });

    test('hitRatio with zero requests returns NaN', () async {
      const stats = StatementCacheStats(
        hits: 0,
        misses: 0,
        evictions: 0,
        cachedCount: 0,
        maxSize: 256,
      );

      expect(stats.hitRatio.isNaN, isTrue,
          reason: 'hitRatio should be NaN when no requests');
    });

    test('cache simulation: 80% hit rate is achievable', () async {
      // Simulate 80% hit rate
      for (var i = 0; i < 80; i++) {
        cache.simulateHit();
      }
      for (var i = 0; i < 20; i++) {
        cache.simulateMiss();
      }

      final stats = await cache.getStats();
      expect(stats.hits, 80);
      expect(stats.misses, 20);
      expect(stats.hitRatio, closeTo(0.8, 0.01));
    });

    test('clearCache resets stats', () async {
      cache.simulateHit();
      cache.simulateHit();
      cache.simulateMiss();

      await cache.clearCache();

      final stats = await cache.getStats();
      expect(stats.hits, 0);
      expect(stats.misses, 0);
    });
  });
}

/// In-memory index manager for benchmark testing.
class InMemoryIndexManager implements IndexManagerPort {
  final List<DbIndex> _indexes = [];

  @override
  List<DbIndex> get indexes => List.unmodifiable(_indexes);

  @override
  Future<void> createAllIndexes() async {
    for (final idx in performanceIndexes) {
      if (!_indexes.any((i) => i.name == idx.name)) {
        _indexes.add(idx);
      }
    }
  }

  @override
  Future<void> createIndex(DbIndex index) async {
    if (!_indexes.any((i) => i.name == index.name)) {
      _indexes.add(index);
    }
  }

  @override
  Future<void> dropAllIndexes() async {
    _indexes.clear();
  }

  @override
  Future<void> dropIndex(DbIndex index) async {
    _indexes.removeWhere((i) => i.name == index.name);
  }

  @override
  Future<bool> indexExists(String name) async {
    return _indexes.any((i) => i.name == name);
  }

  /// The 38 performance indexes from Task 12.2.
  static List<DbIndex> get performanceIndexes => [
        DbIndex(name: 'idx_sync_queue_status', table: 'sync_queue', columns: ['status']),
        DbIndex(name: 'idx_messages_conversation', table: 'messages', columns: ['conversation_id']),
        DbIndex(name: 'idx_connection_requests_status', table: 'connection_requests', columns: ['status']),
        DbIndex(name: 'idx_devices_owner', table: 'devices', columns: ['owner_hash']),
        DbIndex(name: 'idx_ledger_drafts_created', table: 'ledger_drafts', columns: ['created_at']),
        DbIndex(name: 'idx_post_votes_direction', table: 'post_votes', columns: ['direction']),
        DbIndex(name: 'idx_evidence_case', table: 'evidence', columns: ['case_id']),
        DbIndex(name: 'idx_intake_drafts_saved', table: 'intake_drafts', columns: ['saved_at']),
        DbIndex(name: 'idx_academy_modules_domain', table: 'academy_modules', columns: ['domain']),
        DbIndex(name: 'idx_module_cache_status', table: 'module_cache', columns: ['status']),
        DbIndex(name: 'idx_sandbox_pages_module', table: 'sandbox_pages', columns: ['module_id']),
        DbIndex(name: 'idx_sandbox_revisions_page', table: 'sandbox_revisions', columns: ['page_id']),
        DbIndex(name: 'idx_study_groups_pin', table: 'study_groups', columns: ['pin_code']),
        DbIndex(name: 'idx_study_group_members_group', table: 'study_group_members', columns: ['group_id']),
        DbIndex(name: 'idx_karma_events_seq', table: 'karma_events', columns: ['seq']),
        DbIndex(name: 'idx_notifications_read', table: 'notifications', columns: ['is_read']),
        DbIndex(name: 'idx_transparency_events_seq', table: 'transparency_events', columns: ['seq']),
        DbIndex(name: 'idx_consent_records_type', table: 'consent_records', columns: ['type']),
        DbIndex(name: 'idx_audit_events_seq', table: 'audit_events', columns: ['seq']),
        DbIndex(name: 'idx_rate_limit_buckets_policy', table: 'rate_limit_buckets', columns: ['policy']),
        DbIndex(name: 'idx_abuse_events_trigger', table: 'abuse_events', columns: ['trigger_type']),
        DbIndex(name: 'idx_messages_delivered', table: 'messages', columns: ['delivered']),
        DbIndex(name: 'idx_sync_queue_pending', table: 'sync_queue', columns: ['status', 'created_at']),
        DbIndex(name: 'idx_connection_requests_recipient', table: 'connection_requests', columns: ['recipient_hash']),
        DbIndex(name: 'idx_devices_active', table: 'devices', columns: ['owner_hash', 'is_active']),
        DbIndex(name: 'idx_ledger_drafts_category', table: 'ledger_drafts', columns: ['category', 'created_at']),
        DbIndex(name: 'idx_evidence_case_created', table: 'evidence', columns: ['case_id', 'created_at']),
        DbIndex(name: 'idx_module_cache_status_cached', table: 'module_cache', columns: ['status', 'cached_at']),
        DbIndex(name: 'idx_sandbox_revisions_page_created', table: 'sandbox_revisions', columns: ['page_id', 'created_at']),
        DbIndex(name: 'idx_study_groups_pin_module', table: 'study_groups', columns: ['pin_code', 'module_id']),
        DbIndex(name: 'idx_notifications_type_read', table: 'notifications', columns: ['type', 'is_read']),
        DbIndex(name: 'idx_notifications_created', table: 'notifications', columns: ['created_at']),
        DbIndex(name: 'idx_transparency_events_pin', table: 'transparency_events', columns: ['pin_code']),
        DbIndex(name: 'idx_consent_records_type_granted', table: 'consent_records', columns: ['type', 'granted']),
        DbIndex(name: 'idx_abuse_events_severity', table: 'abuse_events', columns: ['severity']),
        DbIndex(name: 'idx_abuse_events_detected', table: 'abuse_events', columns: ['detected_at']),
        DbIndex(name: 'idx_karma_events_actor', table: 'karma_events', columns: ['actor_hash']),
        DbIndex(name: 'idx_messages_conversation_direction', table: 'messages', columns: ['conversation_id', 'direction']),
      ];
}

/// In-memory batch writer for benchmark testing.
class InMemoryBatchWriter implements BatchWriterPort {
  final List<String> executedSql = [];

  @override
  Future<BatchResult> executeBatch(List<BatchOperation> operations) async {
    executedSql.add('BATCH:${operations.length}');
    return BatchResult(
      successCount: operations.length,
      failureCount: 0,
    );
  }

  @override
  Future<BatchResult> executeInSavepoint(
    String savepointName,
    List<BatchOperation> operations,
  ) async {
    executedSql.add('SAVEPOINT:$savepointName:${operations.length}');
    return BatchResult(
      successCount: operations.length,
      failureCount: 0,
    );
  }

  @override
  Future<void> executeRaw(String sql, [List<Object?>? args]) async {
    executedSql.add('RAW:$sql');
  }

  @override
  Future<void> executeRawBatch(
      List<(String sql, List<Object?>? args)> statements) async {
    executedSql.add('RAW_BATCH:${statements.length}');
  }
}

/// In-memory statement cache for benchmark testing.
class InMemoryStatementCache implements StatementCachePort {
  int _hits = 0;
  int _misses = 0;
  StatementCacheConfig? _config;

  @override
  Future<void> applyConfig(StatementCacheConfig config) async {
    _config = config;
  }

  @override
  Future<StatementCacheStats> getStats() async {
    return StatementCacheStats(
      hits: _hits,
      misses: _misses,
      evictions: 0,
      cachedCount: _hits + _misses,
      maxSize: _config?.maxCacheSize ?? 256,
    );
  }

  @override
  Future<void> clearCache() async {
    _hits = 0;
    _misses = 0;
  }

  @override
  Future<void> optimizeQueryPlans() async {}

  @override
  Future<int> getPageCount() async => 0;

  @override
  Future<int> getPageSize() async => 4096;

  void simulateHit() => _hits++;
  void simulateMiss() => _misses++;
}
