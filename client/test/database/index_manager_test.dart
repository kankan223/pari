import 'package:civic_commons/database/data/in_memory_index_manager.dart';
import 'package:civic_commons/database/domain/index_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DbIndex - Task 12.2', () {
    test('createSql generates correct CREATE INDEX statement', () {
      const index = DbIndex(
        name: 'idx_test',
        table: 'users',
        columns: ['username'],
      );
      expect(index.createSql, 'CREATE INDEX idx_test ON users (username)');
    });

    test('createSql with UNIQUE generates correct statement', () {
      const index = DbIndex(
        name: 'idx_unique_test',
        table: 'users',
        columns: ['email'],
        unique: true,
      );
      expect(index.createSql,
          'CREATE UNIQUE INDEX idx_unique_test ON users (email)');
    });

    test('createSql with WHERE generates partial index', () {
      const index = DbIndex(
        name: 'idx_partial',
        table: 'sync_queue',
        columns: ['status', 'created_at'],
        where: "status IN ('pending', 'failed')",
      );
      expect(
        index.createSql,
        "CREATE INDEX idx_partial ON sync_queue (status, created_at) WHERE status IN ('pending', 'failed')",
      );
    });

    test('createSql with multiple columns', () {
      const index = DbIndex(
        name: 'idx_multi',
        table: 'messages',
        columns: ['conversation_id', 'direction'],
      );
      expect(index.createSql,
          'CREATE INDEX idx_multi ON messages (conversation_id, direction)');
    });

    test('dropSql generates correct DROP statement', () {
      const index = DbIndex(name: 'idx_test', table: 'users', columns: ['id']);
      expect(index.dropSql, 'DROP INDEX IF EXISTS idx_test');
    });

    test('equality by name', () {
      const a = DbIndex(name: 'idx_1', table: 't', columns: ['c']);
      const b = DbIndex(name: 'idx_1', table: 't', columns: ['c']);
      const c = DbIndex(name: 'idx_2', table: 't', columns: ['c']);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('performanceIndexes - Task 12.2', () {
    test('defines indexes for all high-frequency tables', () {
      // Verify we have indexes for key tables
      final tables = performanceIndexes.map((i) => i.table).toSet();
      expect(tables, contains('sync_queue'));
      expect(tables, contains('messages'));
      expect(tables, contains('connection_requests'));
      expect(tables, contains('devices'));
      expect(tables, contains('evidence'));
      expect(tables, contains('karma_events'));
      expect(tables, contains('notifications'));
      expect(tables, contains('study_groups'));
      expect(tables, contains('consent_records'));
      expect(tables, contains('audit_events'));
    });

    test('all indexes have unique names', () {
      final names = performanceIndexes.map((i) => i.name).toList();
      final uniqueNames = names.toSet();
      expect(names.length, uniqueNames.length,
          reason: 'Duplicate index names found');
    });

    test('all index names start with idx_', () {
      for (final index in performanceIndexes) {
        expect(index.name, startsWith('idx_'),
            reason: '${index.name} must start with idx_');
      }
    });

    test('all index tables exist in the schema', () {
      const validTables = {
        'sync_queue',
        'messages',
        'connection_requests',
        'devices',
        'ledger_drafts',
        'post_votes',
        'peer_reviews',
        'evidence',
        'intake_drafts',
        'academy_domains',
        'academy_modules',
        'academy_progress',
        'module_cache',
        'sandbox_pages',
        'sandbox_revisions',
        'study_groups',
        'study_group_members',
        'karma_events',
        'notifications',
        'transparency_events',
        'consent_records',
        'audit_events',
        'rate_limit_buckets',
        'abuse_events',
        'users',
        'conversations',
      };
      for (final index in performanceIndexes) {
        expect(
          validTables,
          contains(index.table),
          reason: 'Index ${index.name} references unknown table ${index.table}',
        );
      }
    });

    test('total index count is reasonable', () {
      expect(performanceIndexes.length, greaterThanOrEqualTo(30));
      expect(performanceIndexes.length, lessThanOrEqualTo(60));
    });
  });

  group('InMemoryIndexManager - Task 12.2', () {
    late InMemoryIndexManager manager;

    setUp(() {
      manager = InMemoryIndexManager();
    });

    test('initially has no indexes', () {
      expect(manager.indexes, isEmpty);
    });

    test('createAllIndexes creates all performance indexes', () async {
      await manager.createAllIndexes();
      expect(manager.indexes.length, performanceIndexes.length);
    });

    test('createIndex adds a single index', () async {
      const index = DbIndex(name: 'idx_test', table: 't', columns: ['c']);
      await manager.createIndex(index);
      expect(manager.indexes, hasLength(1));
      expect(manager.indexes.first.name, 'idx_test');
    });

    test('dropIndex removes an index', () async {
      const index = DbIndex(name: 'idx_test', table: 't', columns: ['c']);
      await manager.createIndex(index);
      await manager.dropIndex(index);
      expect(manager.indexes, isEmpty);
    });

    test('dropAllIndexes clears all indexes', () async {
      await manager.createAllIndexes();
      await manager.dropAllIndexes();
      expect(manager.indexes, isEmpty);
    });

    test('indexExists returns true for created index', () async {
      await manager.createAllIndexes();
      expect(await manager.indexExists('idx_sync_queue_status'), isTrue);
      expect(await manager.indexExists('idx_nonexistent'), isFalse);
    });

    test('createIndex is idempotent', () async {
      const index = DbIndex(name: 'idx_test', table: 't', columns: ['c']);
      await manager.createIndex(index);
      await manager.createIndex(index);
      expect(manager.indexes, hasLength(1));
    });
  });
}
