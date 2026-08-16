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
      // v4 (CREATE TABLE devices) + v5 (CREATE TABLE ledger_drafts) +
      // v6 (CREATE TABLE post_votes) + v7 (CREATE TABLE peer_reviews).
      expect(
        executor.executed.length,
        AppSchema.tables.length + 7,
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
      expect(
        executor.executed,
        anyElement(startsWith('CREATE TABLE ledger_drafts (')),
      );
      expect(
        executor.executed,
        anyElement(startsWith('CREATE TABLE post_votes (')),
      );
      expect(
        executor.executed,
        anyElement(startsWith('CREATE TABLE peer_reviews (')),
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

      // v1 + v2 + v3 + v4 + v5 + v6 + v7 applied once; version ends at current.
      expect(
        executor.executed.length,
        AppSchema.tables.length + 7,
      );
      expect(executor.version, AppSchema.currentVersion);
    });

    test(
        'a v1 database upgrades to the current version with the ALTERs/CREATEs',
        () async {
      final executor = FakeMigrationExecutor()..version = 1;
      final runner = MigrationRunner(executor);

      await runner.migrate();

      expect(executor.executed.length, 7);
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
      expect(
        executor.executed[4],
        startsWith('CREATE TABLE ledger_drafts ('),
      );
      expect(
        executor.executed[5],
        startsWith('CREATE TABLE post_votes ('),
      );
      expect(
        executor.executed[6],
        startsWith('CREATE TABLE peer_reviews ('),
      );
      expect(executor.version, AppSchema.currentVersion);
    });

    test(
        'a v2 database upgrades to the current version (v3 ALTERs + v4/v5 CREATEs)',
        () async {
      final executor = FakeMigrationExecutor()..version = 2;
      final runner = MigrationRunner(executor);

      await runner.migrate();

      expect(executor.executed.length, 6);
      expect(executor.executed[0], contains('ADD COLUMN direction'));
      expect(executor.executed[1], contains("SET direction = 'sent'"));
      expect(executor.executed[2], startsWith('CREATE TABLE devices ('));
      expect(executor.executed[3], startsWith('CREATE TABLE ledger_drafts ('));
      expect(executor.executed[4], startsWith('CREATE TABLE post_votes ('));
      expect(executor.executed[5], startsWith('CREATE TABLE peer_reviews ('));
      expect(executor.version, AppSchema.currentVersion);
    });

    test('a v3 database upgrades to v4 with the devices CREATE TABLE',
        () async {
      final executor = FakeMigrationExecutor()..version = 3;
      final runner = MigrationRunner(executor);

      await runner.migrate();

      expect(executor.executed.length, 4);
      expect(executor.executed[0], startsWith('CREATE TABLE devices ('));
      expect(
        executor.executed[1],
        startsWith('CREATE TABLE ledger_drafts ('),
      );
      expect(
        executor.executed[2],
        startsWith('CREATE TABLE post_votes ('),
      );
      expect(
        executor.executed[3],
        startsWith('CREATE TABLE peer_reviews ('),
      );
      expect(executor.version, AppSchema.currentVersion);
    });

    test('a v4 database upgrades to v5 with the ledger_drafts CREATE TABLE',
        () async {
      final executor = FakeMigrationExecutor()..version = 4;
      final runner = MigrationRunner(executor);

      await runner.migrate();

      expect(executor.executed.length, 3);
      expect(
        executor.executed[0],
        startsWith('CREATE TABLE ledger_drafts ('),
      );
      expect(
        executor.executed[1],
        startsWith('CREATE TABLE post_votes ('),
      );
      expect(
        executor.executed[2],
        startsWith('CREATE TABLE peer_reviews ('),
      );
      expect(executor.version, AppSchema.currentVersion);
    });

    test('a v5 database upgrades to v6 with the post_votes CREATE TABLE',
        () async {
      final executor = FakeMigrationExecutor()..version = 5;
      final runner = MigrationRunner(executor);

      await runner.migrate();

      expect(executor.executed.length, 2);
      expect(
        executor.executed[0],
        startsWith('CREATE TABLE post_votes ('),
      );
      expect(
        executor.executed[1],
        startsWith('CREATE TABLE peer_reviews ('),
      );
      expect(executor.version, AppSchema.currentVersion);
    });

    test('a v6 database upgrades to v7 with the peer_reviews CREATE TABLE',
        () async {
      final executor = FakeMigrationExecutor()..version = 6;
      final runner = MigrationRunner(executor);

      await runner.migrate();

      expect(executor.executed.length, 1);
      expect(
        executor.executed.first,
        startsWith('CREATE TABLE peer_reviews ('),
      );
      expect(executor.version, AppSchema.currentVersion);
    });

    test('v4 rolls back by dropping the devices table', () {
      final v4 = AppMigrations.all.firstWhere((m) => m.version == 4);
      expect(v4.downStatements, isNotNull);
      expect(v4.downStatements!.first, contains('DROP TABLE devices'));
    });

    test('v5 rolls back by dropping the ledger_drafts table', () {
      final v5 = AppMigrations.all.firstWhere((m) => m.version == 5);
      expect(v5.downStatements, isNotNull);
      expect(v5.downStatements!.first, contains('DROP TABLE ledger_drafts'));
    });

    test('v6 rolls back by dropping the post_votes table', () {
      final v6 = AppMigrations.all.firstWhere((m) => m.version == 6);
      expect(v6.downStatements, isNotNull);
      expect(v6.downStatements!.first, contains('DROP TABLE post_votes'));
    });

    test('v7 rolls back by dropping the peer_reviews table', () {
      final v7 = AppMigrations.all.firstWhere((m) => m.version == 7);
      expect(v7.downStatements, isNotNull);
      expect(v7.downStatements!.first, contains('DROP TABLE peer_reviews'));
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
