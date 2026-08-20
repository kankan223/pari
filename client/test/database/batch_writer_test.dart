import 'package:civic_commons/database/data/in_memory_batch_writer.dart';
import 'package:civic_commons/database/domain/batch_writer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BatchOperation - Task 12.2', () {
    test('insert factory creates correct operation', () {
      const op = BatchOperation.insert(
        table: 'users',
        row: {'id': '1', 'name': 'test'},
      );
      expect(op.type, BatchOperationType.insert);
      expect(op.table, 'users');
      expect(op.row?['id'], '1');
      expect(op.replace, isFalse);
    });

    test('insert with replace', () {
      const op = BatchOperation.insert(
        table: 'users',
        row: {'id': '1'},
        replace: true,
      );
      expect(op.replace, isTrue);
    });

    test('update factory creates correct operation', () {
      const op = BatchOperation.update(
        table: 'users',
        row: {'name': 'updated'},
        where: 'id = ?',
        whereArgs: ['1'],
      );
      expect(op.type, BatchOperationType.update);
      expect(op.where, 'id = ?');
      expect(op.whereArgs, ['1']);
    });

    test('delete factory creates correct operation', () {
      const op = BatchOperation.delete(
        table: 'users',
        where: 'id = ?',
        whereArgs: ['1'],
      );
      expect(op.type, BatchOperationType.delete);
      expect(op.where, 'id = ?');
    });

    test('raw factory creates correct operation', () {
      const op = BatchOperation.raw(
        sql: 'CREATE INDEX idx_test ON users (id)',
      );
      expect(op.type, BatchOperationType.raw);
      expect(op.rawSql, 'CREATE INDEX idx_test ON users (id)');
    });
  });

  group('BatchResult - Task 12.2', () {
    test('allSucceeded when no failures', () {
      const result = BatchResult(successCount: 10, failureCount: 0);
      expect(result.allSucceeded, isTrue);
      expect(result.totalCount, 10);
    });

    test('allSucceeded false when failures exist', () {
      const result = BatchResult(
        successCount: 8,
        failureCount: 2,
        errors: ['error 1', 'error 2'],
      );
      expect(result.allSucceeded, isFalse);
      expect(result.totalCount, 10);
      expect(result.errors, hasLength(2));
    });
  });

  group('InMemoryBatchWriter - Task 12.2', () {
    late InMemoryBatchWriter writer;

    setUp(() {
      writer = InMemoryBatchWriter();
    });

    test('executeBatch records operations', () async {
      final result = await writer.executeBatch([
        const BatchOperation.insert(table: 't', row: {'id': '1'}),
        const BatchOperation.insert(table: 't', row: {'id': '2'}),
      ]);
      expect(result.successCount, 2);
      expect(result.failureCount, 0);
      expect(writer.batchHistory, hasLength(1));
      expect(writer.totalOperations, 2);
    });

    test('executeBatch returns success for all operations', () async {
      final result = await writer.executeBatch([
        const BatchOperation.insert(table: 't', row: {'id': '1'}),
        const BatchOperation.update(
          table: 't',
          row: {'name': 'x'},
          where: 'id = ?',
          whereArgs: ['1'],
        ),
        const BatchOperation.delete(
          table: 't',
          where: 'id = ?',
          whereArgs: ['1'],
        ),
      ]);
      expect(result.allSucceeded, isTrue);
      expect(result.totalCount, 3);
    });

    test('executeInSavepoint wraps with SAVEPOINT', () async {
      final result = await writer.executeInSavepoint('sp1', [
        const BatchOperation.insert(table: 't', row: {'id': '1'}),
      ]);
      expect(result.successCount, 1);
      // Should have SAVEPOINT + operation + RELEASE
      expect(writer.batchHistory.last.length, 3);
      expect(writer.rawSqlHistory, contains('SAVEPOINT sp1'));
      expect(writer.rawSqlHistory, contains('RELEASE SAVEPOINT sp1'));
    });

    test('executeRaw records SQL', () async {
      await writer.executeRaw('CREATE INDEX idx_test ON t (c)');
      expect(writer.rawSqlHistory, hasLength(1));
      expect(writer.rawSqlHistory.first, 'CREATE INDEX idx_test ON t (c)');
    });

    test('executeRawBatch records multiple SQL statements', () async {
      await writer.executeRawBatch([
        ('CREATE INDEX idx_1 ON t (a)', null),
        ('CREATE INDEX idx_2 ON t (b)', null),
      ]);
      expect(writer.rawSqlHistory, hasLength(2));
    });

    test('reset clears all history', () async {
      await writer.executeBatch([
        const BatchOperation.insert(table: 't', row: {'id': '1'}),
      ]);
      writer.reset();
      expect(writer.batchHistory, isEmpty);
      expect(writer.rawSqlHistory, isEmpty);
      expect(writer.totalOperations, 0);
    });

    test('multiple batches accumulate history', () async {
      await writer.executeBatch([
        const BatchOperation.insert(table: 't', row: {'id': '1'}),
      ]);
      await writer.executeBatch([
        const BatchOperation.insert(table: 't', row: {'id': '2'}),
        const BatchOperation.insert(table: 't', row: {'id': '3'}),
      ]);
      expect(writer.batchHistory, hasLength(2));
      expect(writer.totalOperations, 3);
    });
  });
}
