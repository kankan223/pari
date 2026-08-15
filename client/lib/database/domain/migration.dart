import 'schema.dart';

/// Port for executing SQL against the encrypted database during migrations.
///
/// The domain migration runner depends only on this abstract interface; the
/// concrete SQLCipher executor lives in the data layer and is injected at
/// composition time. Tests use an in-memory fake.
abstract class MigrationExecutor {
  /// Executes one or more SQL statements (no results expected).
  Future<void> execute(String sql);

  /// Reads the current user_version pragma (0 when never set).
  Future<int> getUserVersion();

  /// Sets the user_version pragma.
  Future<void> setUserVersion(int version);
}

/// A single reversible schema migration.
class Migration {
  /// Monotonic version this migration upgrades TO (1 = first).
  final int version;

  /// Human-readable description.
  final String description;

  /// SQL executed to apply this migration (upgrade).
  final List<String> upStatements;

  /// SQL executed to roll back this migration (downgrade), if any.
  final List<String>? downStatements;

  const Migration({
    required this.version,
    required this.description,
    required this.upStatements,
    this.downStatements,
  });
}

/// The built-in migration set for the app schema.
///
/// Migration 1 creates all five core tables.
final class AppMigrations {
  AppMigrations._();

  /// NOTE: `final`, not `const` — `AppSchema.createAllTableSql()` is a method
  /// call (builds SQL at runtime), which is illegal inside a const list.
  static final List<Migration> all = [
    Migration(
      version: 1,
      description: 'Create core tables (users, conversations, messages, '
          'connection_requests, sync_queue)',
      upStatements: AppSchema.createAllTableSql(),
    ),
    const Migration(
      version: 2,
      description: 'Add sync_queue.last_attempt_at for retry gating (Task 5.2)',
      upStatements: [
        'ALTER TABLE sync_queue ADD COLUMN last_attempt_at INTEGER',
      ],
      downStatements: [
        'ALTER TABLE sync_queue DROP COLUMN last_attempt_at',
      ],
    ),
    const Migration(
      version: 3,
      description:
          'Add messages.direction for explicit sent/received (Task 6.3)',
      upStatements: [
        // ADD COLUMN with NOT NULL requires a default for existing rows; then
        // backfill by the pre-6.3 heuristic so already-delivered (received)
        // vs locally-created undelivered (sent) messages keep their side.
        "ALTER TABLE messages ADD COLUMN direction TEXT NOT NULL DEFAULT 'received'",
        "UPDATE messages SET direction = 'sent' WHERE delivered = 0",
      ],
      downStatements: [
        'ALTER TABLE messages DROP COLUMN direction',
      ],
    ),
    const Migration(
      version: 4,
      description: 'Add devices table for locally linked devices (Task 6.5)',
      upStatements: [
        // Devices carry ONLY blind hashes + opaque public keys (sensitive
        // columns) inside the encrypted database — never phones, never
        // private keys.
        'CREATE TABLE devices (id TEXT PRIMARY KEY NOT NULL, '
            'blind_hash TEXT NOT NULL, public_key BLOB NOT NULL, '
            'paired_at INTEGER NOT NULL, revoked INTEGER NOT NULL)',
      ],
      downStatements: [
        'DROP TABLE devices',
      ],
    ),
  ];
}

/// Domain use case that applies pending migrations in order and tracks the
/// schema version via the SQLite `user_version` pragma.
///
/// Security contract:
/// - Runs inside the encrypted connection, so all DDL is applied to the
///   ciphertext-encrypted database file.
/// - Migration SQL is static and versioned; no runtime data is ever written
///   to the migration statements.
class MigrationRunner {
  final MigrationExecutor _executor;

  const MigrationRunner(this._executor);

  /// Returns migrations whose version is above [currentVersion].
  List<Migration> pending(int currentVersion) => AppMigrations.all
      .where((m) => m.version > currentVersion)
      .toList(growable: false);

  /// Applies every pending migration in ascending version order.
  ///
  /// Throws [MigrationException] if a migration fails; the version pragma is
  /// only advanced AFTER each migration's statements succeed.
  Future<int> migrate() async {
    var version = await _executor.getUserVersion();
    for (final migration in pending(version)) {
      try {
        for (final statement in migration.upStatements) {
          await _executor.execute(statement);
        }
        version = migration.version;
        await _executor.setUserVersion(version);
      } catch (e) {
        throw MigrationException(
          'Migration to v${migration.version} failed: $e',
        );
      }
    }
    return version;
  }
}

/// Thrown when a migration cannot be applied.
class MigrationException implements Exception {
  final String message;

  const MigrationException(this.message);

  @override
  String toString() => 'MigrationException: $message';
}
