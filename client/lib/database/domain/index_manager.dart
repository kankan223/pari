/// Represents a single SQLite index definition (Task 12.2).
///
/// Each index targets a high-frequency read/write path. All values are pure
/// strings and booleans — no identity, no PII.
class DbIndex {
  /// Unique name for this index.
  final String name;

  /// Table the index applies to.
  final String table;

  /// Columns included in the index (in order).
  final List<String> columns;

  /// Whether this is a UNIQUE index.
  final bool unique;

  /// Optional WHERE clause for a partial index (SQLite 3.8.0+).
  final String? where;

  const DbIndex({
    required this.name,
    required this.table,
    required this.columns,
    this.unique = false,
    this.where,
  });

  /// Generates the CREATE INDEX SQL statement.
  String get createSql {
    final uniqueStr = unique ? 'UNIQUE ' : '';
    final cols = columns.join(', ');
    final whereClause = where != null ? ' WHERE $where' : '';
    return 'CREATE ${uniqueStr}INDEX $name ON $table ($cols)$whereClause';
  }

  /// Generates the DROP INDEX SQL statement.
  String get dropSql => 'DROP INDEX IF EXISTS $name';
}

/// Port for managing database indexes.
///
/// Implementations create, drop, and verify indexes on the encrypted database.
/// No identity, no PII — only index metadata.
abstract class IndexManagerPort {
  /// Creates all performance indexes defined for the schema.
  Future<void> createAllIndexes();

  /// Drops all indexes (for testing/migration rollback).
  Future<void> dropAllIndexes();

  /// Returns the list of currently defined indexes.
  List<DbIndex> get indexes;

  /// Creates a single index.
  Future<void> createIndex(DbIndex index);

  /// Drops a single index.
  Future<void> dropIndex(DbIndex index);

  /// Returns true if the index exists in the database.
  Future<bool> indexExists(String name);
}
