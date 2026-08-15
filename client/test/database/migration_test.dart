import 'package:flutter_test/flutter_test.dart';
import 'package:civic_commons/database/domain/migration.dart';
import 'package:civic_commons/database/domain/schema.dart';

/// In-memory migration executor recording executed statements.
class FakeMigrationExecutor implements MigrationExecutor {
  int version = 0;
  final List<String> executed = [];
  bool failNext = false;

  @override
  Future<void> execute(String sql) async {
    if (failNext) {
      failNext = false;
      throw Exception('statement failed');
    }
    executed.add(sql);
  }

  @override
  Future<int> getUserVersion() async => version;

  @override
  Future<void> setUserVersion(int version) async {
    this.version = version;
  }
}

void main() {
  group('MigrationRunner - schema creation', () {
    test('migrates a fresh database to the current version', () async {
      final executor = FakeMigrationExecutor();
      final runner = MigrationRunner(executor);

      final finalVersion = await runner.migrate();

      expect(finalVersion, AppSchema.currentVersion);
      expect(executor.version, AppSchema.currentVersion);
      // v1 CREATE TABLEs (one per table) + v2 ALTER + v3 (ALTER + UPDATE) +
      // v4 (CREATE TABLE devices).
      expect(
        executor.executed.length,
        AppSchema.tables.length + 4,
      );
      expect(
        executor.executed.first,
        startsWith('CREATE TABLE users ('),
      );
      expect(
        executor.executed,
        anyElement(startsWith('CREATE TABLE sync_queue (')),
      );
      expect(
        executor.executed,
        anyElement(startsWith('CREATE TABLE devices (')),
      );
      // v2 adds the retry-gating timestamp column (Task 5.2).
      expect(
        executor.executed,
        anyElement(
            contains('ALTER TABLE sync_queue ADD COLUMN last_attempt_at')),
      ); // v3 adds the explicit message direction column (Task 6.3).
      expect(
        executor.executed,
        anyElement(contains('ALTER TABLE messages ADD COLUMN direction')),
      );
      // v3 backfills locally-created undelivered messages as 'sent' so the
      // pre-6.3 heuristic rendering is preserved for existing rows.
      expect(
        executor.executed,
        anyElement(contains("SET direction = 'sent'")),
      );
    });
  });

  group('MigrationRunner - incremental upgrades', () {
    test('does nothing when already at the current version', () async {
      final executor = FakeMigrationExecutor()
        ..version = AppSchema.currentVersion;
      final runner = MigrationRunner(executor);

      final finalVersion = await runner.migrate();

      expect(finalVersion, AppSchema.currentVersion);
      expect(executor.executed, isEmpty);
    });

    test('applies only pending migrations above the current version', () async {
      final executor = FakeMigrationExecutor()..version = 0;
      final runner = MigrationRunner(executor);

      await runner.migrate();

      // v1 + v2 + v3 + v4 applied once; version ends at current.
      expect(
        executor.executed.length,
        AppSchema.tables.length + 4,
      );
      expect(executor.version, AppSchema.currentVersion);
    });

    test(
        'a v1 database upgrades to the current version with the ALTERs/CREATEs',
        () async {
      final executor = FakeMigrationExecutor()..version = 1;
      final runner = MigrationRunner(executor);

      await runner.migrate();

      expect(executor.executed.length, 4);
      expect(
        executor.executed[0],
        contains('ADD COLUMN last_attempt_at'),
      );
      expect(
        executor.executed[1],
        contains('ADD COLUMN direction'),
      );
      expect(
        executor.executed[2],
        contains("SET direction = 'sent'"),
      );
      expect(
        executor.executed[3],
        startsWith('CREATE TABLE devices ('),
      );
      expect(executor.version, AppSchema.currentVersion);
    });

    test(
        'a v2 database upgrades to the current version (v3 ALTERs + v4 devices)',
        () async {
      final executor = FakeMigrationExecutor()..version = 2;
      final runner = MigrationRunner(executor);

      await runner.migrate();

      expect(executor.executed.length, 3);
      expect(executor.executed[0], contains('ADD COLUMN direction'));
      expect(executor.executed[1], contains("SET direction = 'sent'"));
      expect(executor.executed[2], startsWith('CREATE TABLE devices ('));
      expect(executor.version, AppSchema.currentVersion);
    });

    test('a v3 database upgrades to v4 with the devices CREATE TABLE',
        () async {
      final executor = FakeMigrationExecutor()..version = 3;
      final runner = MigrationRunner(executor);

      await runner.migrate();

      expect(executor.executed.length, 1);
      expect(executor.executed.first, startsWith('CREATE TABLE devices ('));
      expect(executor.version, AppSchema.currentVersion);
    });

    test('v4 rolls back by dropping the devices table', () {
      final v4 = AppMigrations.all.firstWhere((m) => m.version == 4);
      expect(v4.downStatements, isNotNull);
      expect(v4.downStatements!.first, contains('DROP TABLE devices'));
    });

    test('version pragma advances only after successful statements', () async {
      final executor = FakeMigrationExecutor();
      final runner = MigrationRunner(executor);

      executor.failNext = true;
      await expectLater(
        runner.migrate(),
        throwsA(isA<MigrationException>()),
      );

      // First statement failed → version must NOT have advanced.
      expect(executor.version, 0);
    });
  });

  group('MigrationRunner - idempotency', () {
    test('a second migrate() call is a no-op', () async {
      final executor = FakeMigrationExecutor();
      final runner = MigrationRunner(executor);

      await runner.migrate();
      final executedAfterFirst = executor.executed.length;
      await runner.migrate();

      expect(executor.executed.length, executedAfterFirst);
      expect(executor.version, AppSchema.currentVersion);
    });
  });
}
