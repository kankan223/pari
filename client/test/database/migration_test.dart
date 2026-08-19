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
      // v6 (CREATE TABLE post_votes) + v7 (CREATE TABLE peer_reviews) +
      // v8 (CREATE TABLE evidence) + v9 (CREATE TABLE intake_drafts) +
      // v10 (3 CREATE TABLEs: academy_domains/modules/progress) +
      // v11 (CREATE TABLE module_cache) +
      // v12 (2 CREATE TABLEs: sandbox_pages/sandbox_revisions) +
      // v13 (2 CREATE TABLEs: study_groups/study_group_members) +
      // v14 (CREATE TABLE karma_events) +
      // v15 (CREATE TABLE notifications) +
      // v16 (CREATE TABLE transparency_events) +
      // v17 (CREATE TABLE consent_records) +
      // v18 (CREATE TABLE audit_events) +
      // v19 (CREATE TABLE rate_limit_buckets + abuse_events) =
      // 26 table creates + 24 migration statements.
      expect(
        executor.executed.length,
        AppSchema.tables.length + 24,
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
      expect(
        executor.executed,
        anyElement(startsWith('CREATE TABLE evidence (')),
      );
      expect(
        executor.executed,
        anyElement(startsWith('CREATE TABLE intake_drafts (')),
      );
      expect(
        executor.executed,
        anyElement(startsWith('CREATE TABLE academy_domains (')),
      );
      expect(
        executor.executed,
        anyElement(startsWith('CREATE TABLE academy_modules (')),
      );
      expect(
        executor.executed,
        anyElement(startsWith('CREATE TABLE academy_progress (')),
      );
      expect(
        executor.executed,
        anyElement(startsWith('CREATE TABLE module_cache (')),
      );
      expect(
        executor.executed,
        anyElement(startsWith('CREATE TABLE sandbox_pages (')),
      );
      expect(
        executor.executed,
        anyElement(startsWith('CREATE TABLE sandbox_revisions (')),
      );
      expect(
        executor.executed,
        anyElement(startsWith('CREATE TABLE study_groups (')),
      );
      expect(
        executor.executed,
        anyElement(startsWith('CREATE TABLE study_group_members (')),
      );
      // v14 adds the append-only karma event ledger (Task 10.2).
      expect(
        executor.executed,
        anyElement(startsWith('CREATE TABLE karma_events (')),
      );
      // v15 adds the local notification store (Task 10.4).
      expect(
        executor.executed,
        anyElement(startsWith('CREATE TABLE notifications (')),
      );
      // v16 adds the append-only transparency audit log (Task 10.5).
      expect(
        executor.executed,
        anyElement(startsWith('CREATE TABLE transparency_events (')),
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

      // v1..v19 applied once; version ends at current.
      expect(
        executor.executed.length,
        AppSchema.tables.length + 24,
      );
      expect(executor.version, AppSchema.currentVersion);
    });

    test(
        'a v1 database upgrades to the current version with the ALTERs/CREATEs',
        () async {
      final executor = FakeMigrationExecutor()..version = 1;
      final runner = MigrationRunner(executor);

      await runner.migrate();

      expect(executor.executed.length, 24);
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
      expect(
        executor.executed[7],
        startsWith('CREATE TABLE evidence ('),
      );
      expect(
        executor.executed[8],
        startsWith('CREATE TABLE intake_drafts ('),
      );
      expect(
        executor.executed[9],
        startsWith('CREATE TABLE academy_domains ('),
      );
      expect(
        executor.executed[10],
        startsWith('CREATE TABLE academy_modules ('),
      );
      expect(
        executor.executed[11],
        startsWith('CREATE TABLE academy_progress ('),
      );
      expect(
        executor.executed[12],
        startsWith('CREATE TABLE module_cache ('),
      );
      expect(
        executor.executed[13],
        startsWith('CREATE TABLE sandbox_pages ('),
      );
      expect(
        executor.executed[14],
        startsWith('CREATE TABLE sandbox_revisions ('),
      );
      expect(
        executor.executed[15],
        startsWith('CREATE TABLE study_groups ('),
      );
      expect(
        executor.executed[16],
        startsWith('CREATE TABLE study_group_members ('),
      );
      expect(
        executor.executed[17],
        startsWith('CREATE TABLE karma_events ('),
      );
      expect(
        executor.executed[18],
        startsWith('CREATE TABLE notifications ('),
      );
      expect(
        executor.executed[19],
        startsWith('CREATE TABLE transparency_events ('),
      );
      expect(
        executor.executed[20],
        startsWith('CREATE TABLE consent_records ('),
      );
      expect(
        executor.executed[21],
        startsWith('CREATE TABLE audit_events ('),
      );
      expect(executor.version, AppSchema.currentVersion);
    });

    test(
        'a v2 database upgrades to the current version (v3 ALTERs + v4/v5 CREATEs)',
        () async {
      final executor = FakeMigrationExecutor()..version = 2;
      final runner = MigrationRunner(executor);

      await runner.migrate(); // v3 (2) + v4..v9 (1 each) + v10 (3) + v11 (1) + v12 (2) + v13 (2) + v14 (1) + v15 (1) + v16 (1) + v17 (1) + v18 (1) + v19 (2) = 23.
      expect(executor.executed.length, 23);
      expect(executor.executed[0], contains('ADD COLUMN direction'));
      expect(executor.executed[1], contains("SET direction = 'sent'"));
      expect(executor.executed[2], startsWith('CREATE TABLE devices ('));
      expect(executor.executed[3], startsWith('CREATE TABLE ledger_drafts ('));
      expect(executor.executed[4], startsWith('CREATE TABLE post_votes ('));
      expect(executor.executed[5], startsWith('CREATE TABLE peer_reviews ('));
      expect(executor.executed[6], startsWith('CREATE TABLE evidence ('));
      expect(executor.executed[7], startsWith('CREATE TABLE intake_drafts ('));
      expect(
          executor.executed[8], startsWith('CREATE TABLE academy_domains ('));
      expect(
          executor.executed[9], startsWith('CREATE TABLE academy_modules ('));
      expect(
          executor.executed[10], startsWith('CREATE TABLE academy_progress ('));
      expect(executor.executed[11], startsWith('CREATE TABLE module_cache ('));
      expect(executor.executed[12], startsWith('CREATE TABLE sandbox_pages ('));
      expect(executor.executed[13],
          startsWith('CREATE TABLE sandbox_revisions ('));
      expect(executor.executed[14], startsWith('CREATE TABLE study_groups ('));
      expect(executor.executed[15],
          startsWith('CREATE TABLE study_group_members ('));
      expect(executor.executed[16], startsWith('CREATE TABLE karma_events ('));
      expect(executor.executed[17], startsWith('CREATE TABLE notifications ('));
      expect(executor.version, AppSchema.currentVersion);
    });

    test('a v3 database upgrades to v4 with the devices CREATE TABLE',
        () async {
      final executor = FakeMigrationExecutor()..version = 3;
      final runner = MigrationRunner(executor);

      await runner.migrate();

      expect(executor.executed.length, 21);
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
      expect(
        executor.executed[4],
        startsWith('CREATE TABLE evidence ('),
      );
      expect(
        executor.executed[5],
        startsWith('CREATE TABLE intake_drafts ('),
      );
      expect(
        executor.executed[6],
        startsWith('CREATE TABLE academy_domains ('),
      );
      expect(
        executor.executed[7],
        startsWith('CREATE TABLE academy_modules ('),
      );
      expect(
        executor.executed[8],
        startsWith('CREATE TABLE academy_progress ('),
      );
      expect(
        executor.executed[9],
        startsWith('CREATE TABLE module_cache ('),
      );
      expect(
        executor.executed[10],
        startsWith('CREATE TABLE sandbox_pages ('),
      );
      expect(
        executor.executed[11],
        startsWith('CREATE TABLE sandbox_revisions ('),
      );
      final len = executor.executed.length;
      expect(
        executor.executed[len - 9],
        startsWith('CREATE TABLE study_groups ('),
      );
      expect(
        executor.executed[len - 8],
        startsWith('CREATE TABLE study_group_members ('),
      );
      expect(
        executor.executed[len - 7],
        startsWith('CREATE TABLE karma_events ('),
      );
      expect(
        executor.executed[len - 6],
        startsWith('CREATE TABLE notifications ('),
      );
      expect(
        executor.executed[len - 5],
        startsWith('CREATE TABLE transparency_events ('),
      );
      expect(
        executor.executed[len - 4],
        startsWith('CREATE TABLE consent_records ('),
      );
      expect(
        executor.executed[len - 3],
        startsWith('CREATE TABLE audit_events ('),
      );
      expect(
        executor.executed[len - 2],
        startsWith('CREATE TABLE rate_limit_buckets ('),
      );
      expect(
        executor.executed[len - 1],
        startsWith('CREATE TABLE abuse_events ('),
      );
      expect(executor.version, AppSchema.currentVersion);
    });

    test('a v4 database upgrades to v5 with the ledger_drafts CREATE TABLE',
        () async {
      final executor = FakeMigrationExecutor()..version = 4;
      final runner = MigrationRunner(executor);

      await runner.migrate();

      expect(executor.executed.length, 20);
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
      expect(
        executor.executed[3],
        startsWith('CREATE TABLE evidence ('),
      );
      expect(
        executor.executed[4],
        startsWith('CREATE TABLE intake_drafts ('),
      );
      expect(
        executor.executed[5],
        startsWith('CREATE TABLE academy_domains ('),
      );
      expect(
        executor.executed[6],
        startsWith('CREATE TABLE academy_modules ('),
      );
      expect(
        executor.executed[7],
        startsWith('CREATE TABLE academy_progress ('),
      );
      expect(
        executor.executed[8],
        startsWith('CREATE TABLE module_cache ('),
      );
      expect(
        executor.executed[9],
        startsWith('CREATE TABLE sandbox_pages ('),
      );
      expect(
        executor.executed[10],
        startsWith('CREATE TABLE sandbox_revisions ('),
      );
      final len = executor.executed.length;
      expect(
        executor.executed[len - 9],
        startsWith('CREATE TABLE study_groups ('),
      );
      expect(
        executor.executed[len - 8],
        startsWith('CREATE TABLE study_group_members ('),
      );
      expect(
        executor.executed[len - 7],
        startsWith('CREATE TABLE karma_events ('),
      );
      expect(
        executor.executed[len - 6],
        startsWith('CREATE TABLE notifications ('),
      );
      expect(
        executor.executed[len - 5],
        startsWith('CREATE TABLE transparency_events ('),
      );
      expect(
        executor.executed[len - 4],
        startsWith('CREATE TABLE consent_records ('),
      );
      expect(
        executor.executed[len - 3],
        startsWith('CREATE TABLE audit_events ('),
      );
      expect(
        executor.executed[len - 2],
        startsWith('CREATE TABLE rate_limit_buckets ('),
      );
      expect(
        executor.executed[len - 1],
        startsWith('CREATE TABLE abuse_events ('),
      );
      expect(executor.version, AppSchema.currentVersion);
    });

    test('a v5 database upgrades to v6 with the post_votes CREATE TABLE',
        () async {
      final executor = FakeMigrationExecutor()..version = 5;
      final runner = MigrationRunner(executor);

      await runner.migrate();

      expect(executor.executed.length, 19);
      expect(
        executor.executed[0],
        startsWith('CREATE TABLE post_votes ('),
      );
      expect(
        executor.executed[1],
        startsWith('CREATE TABLE peer_reviews ('),
      );
      expect(
        executor.executed[2],
        startsWith('CREATE TABLE evidence ('),
      );
      expect(
        executor.executed[3],
        startsWith('CREATE TABLE intake_drafts ('),
      );
      expect(
        executor.executed[4],
        startsWith('CREATE TABLE academy_domains ('),
      );
      expect(
        executor.executed[5],
        startsWith('CREATE TABLE academy_modules ('),
      );
      expect(
        executor.executed[6],
        startsWith('CREATE TABLE academy_progress ('),
      );
      expect(
        executor.executed[7],
        startsWith('CREATE TABLE module_cache ('),
      );
      expect(
        executor.executed[8],
        startsWith('CREATE TABLE sandbox_pages ('),
      );
      expect(
        executor.executed[9],
        startsWith('CREATE TABLE sandbox_revisions ('),
      );
      final len = executor.executed.length;
      expect(
        executor.executed[len - 9],
        startsWith('CREATE TABLE study_groups ('),
      );
      expect(
        executor.executed[len - 8],
        startsWith('CREATE TABLE study_group_members ('),
      );
      expect(
        executor.executed[len - 7],
        startsWith('CREATE TABLE karma_events ('),
      );
      expect(
        executor.executed[len - 6],
        startsWith('CREATE TABLE notifications ('),
      );
      expect(
        executor.executed[len - 5],
        startsWith('CREATE TABLE transparency_events ('),
      );
      expect(
        executor.executed[len - 4],
        startsWith('CREATE TABLE consent_records ('),
      );
      expect(
        executor.executed[len - 3],
        startsWith('CREATE TABLE audit_events ('),
      );
      expect(
        executor.executed[len - 2],
        startsWith('CREATE TABLE rate_limit_buckets ('),
      );
      expect(
        executor.executed[len - 1],
        startsWith('CREATE TABLE abuse_events ('),
      );
      expect(executor.version, AppSchema.currentVersion);
    });

    test('a v6 database upgrades to v7 with the peer_reviews CREATE TABLE',
        () async {
      final executor = FakeMigrationExecutor()..version = 6;
      final runner = MigrationRunner(executor);

      await runner.migrate();

      expect(executor.executed.length, 18);
      expect(
        executor.executed[0],
        startsWith('CREATE TABLE peer_reviews ('),
      );
      expect(executor.executed[1], startsWith('CREATE TABLE evidence ('));
      expect(
        executor.executed[2],
        startsWith('CREATE TABLE intake_drafts ('),
      );
      expect(
        executor.executed[3],
        startsWith('CREATE TABLE academy_domains ('),
      );
      expect(
        executor.executed[4],
        startsWith('CREATE TABLE academy_modules ('),
      );
      expect(
        executor.executed[5],
        startsWith('CREATE TABLE academy_progress ('),
      );
      expect(
        executor.executed[6],
        startsWith('CREATE TABLE module_cache ('),
      );
      expect(
        executor.executed[7],
        startsWith('CREATE TABLE sandbox_pages ('),
      );
      expect(
        executor.executed[8],
        startsWith('CREATE TABLE sandbox_revisions ('),
      );
      final len = executor.executed.length;
      expect(
        executor.executed[len - 9],
        startsWith('CREATE TABLE study_groups ('),
      );
      expect(
        executor.executed[len - 8],
        startsWith('CREATE TABLE study_group_members ('),
      );
      expect(
        executor.executed[len - 7],
        startsWith('CREATE TABLE karma_events ('),
      );
      expect(
        executor.executed[len - 6],
        startsWith('CREATE TABLE notifications ('),
      );
      expect(
        executor.executed[len - 5],
        startsWith('CREATE TABLE transparency_events ('),
      );
      expect(
        executor.executed[len - 4],
        startsWith('CREATE TABLE consent_records ('),
      );
      expect(
        executor.executed[len - 3],
        startsWith('CREATE TABLE audit_events ('),
      );
      expect(
        executor.executed[len - 2],
        startsWith('CREATE TABLE rate_limit_buckets ('),
      );
      expect(
        executor.executed[len - 1],
        startsWith('CREATE TABLE abuse_events ('),
      );
      expect(executor.version, AppSchema.currentVersion);
    });

    test('a v7 database upgrades to v8 with the evidence CREATE TABLE',
        () async {
      final executor = FakeMigrationExecutor()..version = 7;
      final runner = MigrationRunner(executor);

      await runner.migrate();

      expect(executor.executed.length, 17);
      expect(
        executor.executed[0],
        startsWith('CREATE TABLE evidence ('),
      );
      expect(
        executor.executed[1],
        startsWith('CREATE TABLE intake_drafts ('),
      );
      expect(
        executor.executed[2],
        startsWith('CREATE TABLE academy_domains ('),
      );
      expect(
        executor.executed[3],
        startsWith('CREATE TABLE academy_modules ('),
      );
      expect(
        executor.executed[4],
        startsWith('CREATE TABLE academy_progress ('),
      );
      expect(
        executor.executed[5],
        startsWith('CREATE TABLE module_cache ('),
      );
      expect(
        executor.executed[6],
        startsWith('CREATE TABLE sandbox_pages ('),
      );
      expect(
        executor.executed[7],
        startsWith('CREATE TABLE sandbox_revisions ('),
      );
      final len = executor.executed.length;
      expect(
        executor.executed[len - 9],
        startsWith('CREATE TABLE study_groups ('),
      );
      expect(
        executor.executed[len - 8],
        startsWith('CREATE TABLE study_group_members ('),
      );
      expect(
        executor.executed[len - 7],
        startsWith('CREATE TABLE karma_events ('),
      );
      expect(
        executor.executed[len - 6],
        startsWith('CREATE TABLE notifications ('),
      );
      expect(
        executor.executed[len - 5],
        startsWith('CREATE TABLE transparency_events ('),
      );
      expect(
        executor.executed[len - 4],
        startsWith('CREATE TABLE consent_records ('),
      );
      expect(
        executor.executed[len - 3],
        startsWith('CREATE TABLE audit_events ('),
      );
      expect(
        executor.executed[len - 2],
        startsWith('CREATE TABLE rate_limit_buckets ('),
      );
      expect(
        executor.executed[len - 1],
        startsWith('CREATE TABLE abuse_events ('),
      );
      expect(executor.version, AppSchema.currentVersion);
    });

    test('a v8 database upgrades through v9+v10+v11+v12+v13+v14+v15 (13 statements total)',
        () async {
      final executor = FakeMigrationExecutor()..version = 8;
      final runner = MigrationRunner(executor);

      await runner.migrate();

      // v9 (intake_drafts) + v10 (three academy CREATE TABLEs) +
      // v11 (module_cache) + v12 (sandbox_pages/sandbox_revisions).
      expect(executor.executed.length, 16);
      expect(
        executor.executed[0],
        startsWith('CREATE TABLE intake_drafts ('),
      );
      expect(
        executor.executed[1],
        startsWith('CREATE TABLE academy_domains ('),
      );
      expect(
        executor.executed[2],
        startsWith('CREATE TABLE academy_modules ('),
      );
      expect(
        executor.executed[3],
        startsWith('CREATE TABLE academy_progress ('),
      );
      expect(
        executor.executed[4],
        startsWith('CREATE TABLE module_cache ('),
      );
      expect(
        executor.executed[5],
        startsWith('CREATE TABLE sandbox_pages ('),
      );
      expect(
        executor.executed[6],
        startsWith('CREATE TABLE sandbox_revisions ('),
      );
      final len = executor.executed.length;
      expect(
        executor.executed[len - 9],
        startsWith('CREATE TABLE study_groups ('),
      );
      expect(
        executor.executed[len - 8],
        startsWith('CREATE TABLE study_group_members ('),
      );
      expect(
        executor.executed[len - 7],
        startsWith('CREATE TABLE karma_events ('),
      );
      expect(
        executor.executed[len - 6],
        startsWith('CREATE TABLE notifications ('),
      );
      expect(
        executor.executed[len - 5],
        startsWith('CREATE TABLE transparency_events ('),
      );
      expect(
        executor.executed[len - 4],
        startsWith('CREATE TABLE consent_records ('),
      );
      expect(
        executor.executed[len - 3],
        startsWith('CREATE TABLE audit_events ('),
      );
      expect(
        executor.executed[len - 2],
        startsWith('CREATE TABLE rate_limit_buckets ('),
      );
      expect(
        executor.executed[len - 1],
        startsWith('CREATE TABLE abuse_events ('),
      );
      expect(executor.version, AppSchema.currentVersion);
    });

    test(
        'a v9 database upgrades through v10+v11+v12 with the academy '
        'CREATE TABLEs + module_cache + sandbox tables', () async {
      final executor = FakeMigrationExecutor()..version = 9;
      final runner = MigrationRunner(executor);

      await runner.migrate();

      // v10 (three academy CREATE TABLEs) + v11 (module_cache) +
      // v12 (sandbox_pages/sandbox_revisions).
      expect(executor.executed.length, 15);
      expect(
        executor.executed[0],
        startsWith('CREATE TABLE academy_domains ('),
      );
      expect(
        executor.executed[1],
        startsWith('CREATE TABLE academy_modules ('),
      );
      expect(
        executor.executed[2],
        startsWith('CREATE TABLE academy_progress ('),
      );
      expect(
        executor.executed[3],
        startsWith('CREATE TABLE module_cache ('),
      );
      expect(
        executor.executed[4],
        startsWith('CREATE TABLE sandbox_pages ('),
      );
      expect(
        executor.executed[5],
        startsWith('CREATE TABLE sandbox_revisions ('),
      );
      final len = executor.executed.length;
      expect(
        executor.executed[len - 9],
        startsWith('CREATE TABLE study_groups ('),
      );
      expect(
        executor.executed[len - 8],
        startsWith('CREATE TABLE study_group_members ('),
      );
      expect(
        executor.executed[len - 7],
        startsWith('CREATE TABLE karma_events ('),
      );
      expect(
        executor.executed[len - 6],
        startsWith('CREATE TABLE notifications ('),
      );
      expect(
        executor.executed[len - 5],
        startsWith('CREATE TABLE transparency_events ('),
      );
      expect(
        executor.executed[len - 4],
        startsWith('CREATE TABLE consent_records ('),
      );
      expect(
        executor.executed[len - 3],
        startsWith('CREATE TABLE audit_events ('),
      );
      expect(
        executor.executed[len - 2],
        startsWith('CREATE TABLE rate_limit_buckets ('),
      );
      expect(
        executor.executed[len - 1],
        startsWith('CREATE TABLE abuse_events ('),
      );
      expect(executor.version, AppSchema.currentVersion);
    });

    test('a v10 database upgrades through v11+v12+v13+v14+v15 (9 statements total)',
        () async {
      final executor = FakeMigrationExecutor()..version = 10;
      final runner = MigrationRunner(executor);

      await runner.migrate();

      // v11 (module_cache) + v12 (sandbox_pages/sandbox_revisions) +
      // v13 (study_groups/study_group_members) + v14 (karma_events).
      expect(executor.executed.length, 12);
      expect(
        executor.executed[0],
        startsWith('CREATE TABLE module_cache ('),
      );
      expect(
        executor.executed[1],
        startsWith('CREATE TABLE sandbox_pages ('),
      );
      expect(
        executor.executed[2],
        startsWith('CREATE TABLE sandbox_revisions ('),
      );
      final len = executor.executed.length;
      expect(
        executor.executed[len - 9],
        startsWith('CREATE TABLE study_groups ('),
      );
      expect(
        executor.executed[len - 8],
        startsWith('CREATE TABLE study_group_members ('),
      );
      expect(
        executor.executed[len - 7],
        startsWith('CREATE TABLE karma_events ('),
      );
      expect(
        executor.executed[len - 6],
        startsWith('CREATE TABLE notifications ('),
      );
      expect(
        executor.executed[len - 5],
        startsWith('CREATE TABLE transparency_events ('),
      );
      expect(
        executor.executed[len - 4],
        startsWith('CREATE TABLE consent_records ('),
      );
      expect(
        executor.executed[len - 3],
        startsWith('CREATE TABLE audit_events ('),
      );
      expect(
        executor.executed[len - 2],
        startsWith('CREATE TABLE rate_limit_buckets ('),
      );
      expect(
        executor.executed[len - 1],
        startsWith('CREATE TABLE abuse_events ('),
      );
      expect(executor.version, AppSchema.currentVersion);
    });

    test('a v11 database upgrades through v12+v13+v14+v15 (8 statements total)',
        () async {
      final executor = FakeMigrationExecutor()..version = 11;
      final runner = MigrationRunner(executor);

      await runner.migrate();

      // v12 (sandbox_pages/sandbox_revisions) + v13 (study groups) +
      // v14 (karma_events).
      expect(executor.executed.length, 11);
      expect(
        executor.executed[0],
        startsWith('CREATE TABLE sandbox_pages ('),
      );
      expect(
        executor.executed[1],
        startsWith('CREATE TABLE sandbox_revisions ('),
      );
      final len = executor.executed.length;
      expect(
        executor.executed[len - 9],
        startsWith('CREATE TABLE study_groups ('),
      );
      expect(
        executor.executed[len - 8],
        startsWith('CREATE TABLE study_group_members ('),
      );
      expect(
        executor.executed[len - 7],
        startsWith('CREATE TABLE karma_events ('),
      );
      expect(
        executor.executed[len - 6],
        startsWith('CREATE TABLE notifications ('),
      );
      expect(
        executor.executed[len - 5],
        startsWith('CREATE TABLE transparency_events ('),
      );
      expect(
        executor.executed[len - 4],
        startsWith('CREATE TABLE consent_records ('),
      );
      expect(
        executor.executed[len - 3],
        startsWith('CREATE TABLE audit_events ('),
      );
      expect(
        executor.executed[len - 2],
        startsWith('CREATE TABLE rate_limit_buckets ('),
      );
      expect(
        executor.executed[len - 1],
        startsWith('CREATE TABLE abuse_events ('),
      );
      expect(executor.version, AppSchema.currentVersion);
    });

    test(
        'a v12 database upgrades to v13+v14+v15+v16 with the study group + karma + notification + transparency '
        'CREATE TABLEs', () async {
      final executor = FakeMigrationExecutor()..version = 12;
      final runner = MigrationRunner(executor);

      await runner.migrate();

      expect(executor.executed.length, 9);
      expect(
        executor.executed[0],
        startsWith('CREATE TABLE study_groups ('),
      );
      expect(
        executor.executed[1],
        startsWith('CREATE TABLE study_group_members ('),
      );
      expect(
        executor.executed[2],
        startsWith('CREATE TABLE karma_events ('),
      );
      expect(
        executor.executed[3],
        startsWith('CREATE TABLE notifications ('),
      );
      expect(
        executor.executed[4],
        startsWith('CREATE TABLE transparency_events ('),
      );
      expect(executor.version, AppSchema.currentVersion);
    });

    test('v9 rolls back by dropping the intake_drafts table', () {
      final v9 = AppMigrations.all.firstWhere((m) => m.version == 9);
      expect(v9.downStatements, isNotNull);
      expect(v9.downStatements!.first, contains('DROP TABLE intake_drafts'));
    });

    test('v10 rolls back by dropping all three academy tables', () {
      final v10 = AppMigrations.all.firstWhere((m) => m.version == 10);
      expect(v10.downStatements, isNotNull);
      expect(v10.downStatements, hasLength(3));
      expect(v10.downStatements![0], contains('DROP TABLE academy_progress'));
      expect(v10.downStatements![1], contains('DROP TABLE academy_modules'));
      expect(v10.downStatements![2], contains('DROP TABLE academy_domains'));
    });

    test('v11 rolls back by dropping the module_cache table', () {
      final v11 = AppMigrations.all.firstWhere((m) => m.version == 11);
      expect(v11.downStatements, isNotNull);
      expect(v11.downStatements!.first, contains('DROP TABLE module_cache'));
    });

    test('v12 rolls back by dropping both sandbox tables', () {
      final v12 = AppMigrations.all.firstWhere((m) => m.version == 12);
      expect(v12.downStatements, isNotNull);
      expect(v12.downStatements, hasLength(2));
      expect(v12.downStatements![0], contains('DROP TABLE sandbox_revisions'));
      expect(v12.downStatements![1], contains('DROP TABLE sandbox_pages'));
    });

    test('v13 rolls back by dropping both study group tables', () {
      final v13 = AppMigrations.all.firstWhere((m) => m.version == 13);
      expect(v13.downStatements, isNotNull);
      expect(v13.downStatements, hasLength(2));
      expect(
          v13.downStatements![0], contains('DROP TABLE study_group_members'));
      expect(v13.downStatements![1], contains('DROP TABLE study_groups'));
    });

    test('v14 rolls back by dropping the karma_events table', () {
      final v14 = AppMigrations.all.firstWhere((m) => m.version == 14);
      expect(v14.downStatements, isNotNull);
      expect(v14.downStatements!.first, contains('DROP TABLE karma_events'));
    });

    test('v15 rolls back by dropping the notifications table', () {
      final v15 = AppMigrations.all.firstWhere((m) => m.version == 15);
      expect(v15.downStatements, isNotNull);
      expect(v15.downStatements!.first, contains('DROP TABLE notifications'));
    });

    test('v16 rolls back by dropping the transparency_events table', () {
      final v16 = AppMigrations.all.firstWhere((m) => m.version == 16);
      expect(v16.downStatements, isNotNull);
      expect(v16.downStatements!.first, contains('DROP TABLE transparency_events'));
    });

    test('v8 rolls back by dropping the evidence table', () {
      final v8 = AppMigrations.all.firstWhere((m) => m.version == 8);
      expect(v8.downStatements, isNotNull);
      expect(v8.downStatements!.first, contains('DROP TABLE evidence'));
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

    test('v19 rolls back by dropping abuse_events and rate_limit_buckets', () {
      final v19 = AppMigrations.all.firstWhere((m) => m.version == 19);
      expect(v19.downStatements, isNotNull);
      expect(v19.downStatements, hasLength(2));
      expect(v19.downStatements![0], contains('DROP TABLE abuse_events'));
      expect(v19.downStatements![1], contains('DROP TABLE rate_limit_buckets'));
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
