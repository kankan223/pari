/// Represents a single write operation in a batch (Task 12.2).
class BatchOperation {
  /// The type of operation.
  final BatchOperationType type;

  /// Target table name.
  final String table;

  /// Row data as a map (for insert/update).
  final Map<String, Object?>? row;

  /// WHERE clause for update/delete operations.
  final String? where;

  /// WHERE arguments for parameterized queries.
  final List<Object?>? whereArgs;

  /// Whether to use ConflictAlgorithm.replace for inserts.
  final bool replace;

  const BatchOperation({
    required this.type,
    required this.table,
    this.row,
    this.where,
    this.whereArgs,
    this.replace = false,
    this.rawSql,
    this.rawArgs,
  });

  /// Creates an INSERT operation.
  const BatchOperation.insert({
    required String table,
    required Map<String, Object?> row,
    bool replace = false,
  }) : this(
          type: BatchOperationType.insert,
          table: table,
          row: row,
          replace: replace,
        );

  /// Creates an UPDATE operation.
  const BatchOperation.update({
    required String table,
    required Map<String, Object?> row,
    required String where,
    List<Object?>? whereArgs,
  }) : this(
          type: BatchOperationType.update,
          table: table,
          row: row,
          where: where,
          whereArgs: whereArgs,
        );

  /// Creates a DELETE operation.
  const BatchOperation.delete({
    required String table,
    required String where,
    List<Object?>? whereArgs,
  }) : this(
          type: BatchOperationType.delete,
          table: table,
          where: where,
          whereArgs: whereArgs,
        );

  /// Creates a RAW SQL operation.
  const BatchOperation.raw({
    required String sql,
    List<Object?>? args,
  })  : type = BatchOperationType.raw,
        table = '',
        row = null,
        where = null,
        whereArgs = null,
        replace = false,
        rawSql = sql,
        rawArgs = args;

  /// Raw SQL for the operation (only for type == raw).
  final String? rawSql;

  /// Arguments for raw SQL operations.
  final List<Object?>? rawArgs;
}

/// Types of batch operations.
enum BatchOperationType {
  insert,
  update,
  delete,
  raw,
}

/// Result of a batch execution (Task 12.2).
class BatchResult {
  /// Number of operations that succeeded.
  final int successCount;

  /// Number of operations that failed.
  final int failureCount;

  /// Error messages for failed operations (if any).
  final List<String> errors;

  /// Total number of operations attempted.
  int get totalCount => successCount + failureCount;

  /// Whether all operations succeeded.
  bool get allSucceeded => failureCount == 0;

  const BatchResult({
    required this.successCount,
    required this.failureCount,
    this.errors = const [],
  });
}

/// Port for executing batched database operations within transactions.
///
/// Implementations wrap operations in SQLCipher transaction blocks for
/// atomicity and performance. No identity, no PII.
abstract class BatchWriterPort {
  /// Executes a list of operations atomically within a transaction.
  ///
  /// Either ALL operations succeed or NONE are committed.
  Future<BatchResult> executeBatch(List<BatchOperation> operations);

  /// Executes operations within a named savepoint (nested transaction).
  Future<BatchResult> executeInSavepoint(
    String savepointName,
    List<BatchOperation> operations,
  );

  /// Executes a single raw SQL statement within the current transaction context.
  Future<void> executeRaw(String sql, [List<Object?>? args]);

  /// Executes multiple raw SQL statements atomically.
  Future<void> executeRawBatch(
      List<(String sql, List<Object?>? args)> statements);
}
