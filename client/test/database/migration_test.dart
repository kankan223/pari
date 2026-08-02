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
      // All five CREATE TABLE statements executed, in order.
      expect(executor.executed.length, AppSchema.tables.length);
      expect(
        executor.executed.first,
        startsWith('CREATE TABLE users ('),
      );
      expect(
        executor.executed,
        anyElement(startsWith('CREATE TABLE sync_queue (')),
      );
    });
  });

  group('MigrationRunner - incremental upgrades', () {
    test('does nothing when already at the current version', () async {
      final executor = FakeMigrationExecutor()..version = AppSchema.currentVersion;
      final runner = MigrationRunner(executor);

      final finalVersion = await runner.migrate();

      expect(finalVersion, AppSchema.currentVersion);
      expect(executor.executed, isEmpty);
    });

    test('applies only pending migrations above the current version', () async {
      final executor = FakeMigrationExecutor()..version = 0;
      final runner = MigrationRunner(executor);

      await runner.migrate();

      // v1 applied once; version ends at current.
      expect(executor.executed.length, AppSchema.tables.length);
      expect(executor.version, AppSchema.currentVersion);
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
