import '../domain/batch_writer.dart';

/// In-memory implementation of [BatchWriterPort] for tests (Task 12.2).
///
/// Records all operations for verification without an actual database.
/// Simulates transaction atomicity by tracking operation counts.
class InMemoryBatchWriter implements BatchWriterPort {
  /// History of all executed batches (for test verification).
  final List<List<BatchOperation>> batchHistory = [];

  /// Total number of operations executed across all batches.
  int get totalOperations =>
      batchHistory.fold(0, (sum, batch) => sum + batch.length);

  /// Total number of raw SQL statements executed.
  int get rawSqlCount => batchHistory
      .expand((b) => b)
      .where((op) => op.type == BatchOperationType.raw)
      .length;

  /// All raw SQL statements executed (in order).
  final List<String> rawSqlHistory = [];

  @override
  Future<BatchResult> executeBatch(List<BatchOperation> operations) async {
    batchHistory.add(List.unmodifiable(operations));
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
    // Add a SAVEPOINT + RELEASE bookend to the history
    final spSql = 'SAVEPOINT $savepointName';
    final releaseSql = 'RELEASE SAVEPOINT $savepointName';
    rawSqlHistory.add(spSql);
    rawSqlHistory.add(releaseSql);
    batchHistory.add([
      BatchOperation.raw(sql: spSql),
      ...operations,
      BatchOperation.raw(sql: releaseSql),
    ]);
    return BatchResult(
      successCount: operations.length,
      failureCount: 0,
    );
  }

  @override
  Future<void> executeRaw(String sql, [List<Object?>? args]) async {
    rawSqlHistory.add(sql);
    batchHistory.add([BatchOperation.raw(sql: sql, args: args)]);
  }

  @override
  Future<void> executeRawBatch(
    List<(String sql, List<Object?>? args)> statements,
  ) async {
    final ops = <BatchOperation>[];
    for (final (sql, args) in statements) {
      rawSqlHistory.add(sql);
      ops.add(BatchOperation.raw(sql: sql, args: args));
    }
    batchHistory.add(ops);
  }

  /// Clears all history (for test isolation).
  void reset() {
    batchHistory.clear();
    rawSqlHistory.clear();
  }
}
