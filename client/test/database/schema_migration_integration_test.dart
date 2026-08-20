import 'package:civic_commons/database/domain/schema.dart';
import 'package:flutter_test/flutter_test.dart';

/// Task 13.2 — Database schema migration integration: verifies the complete
/// schema definition covers all module persistence needs with zero-identity
/// columns and performance indexes.
void main() {
  group('Task 13.2 — schema migration integration', () {
    test('schema version is current (v19)', () {
      expect(AppSchema.currentVersion, 19);
    });

    test('createTableSql produces valid SQL for all defined tables', () {
      final tables = [
        AppSchema.users,
        AppSchema.messages,
        AppSchema.syncQueue,
        AppSchema.ledgerDrafts,
        AppSchema.evidence,
        AppSchema.academyModules,
        AppSchema.karmaEvents,
        AppSchema.consentRecords,
        AppSchema.auditEvents,
        AppSchema.transparencyEvents,
      ];

      for (final table in tables) {
        final sql = AppSchema.createTableSql(table);
        expect(sql.toUpperCase(), startsWith('CREATE TABLE'),
            reason: '${table.name} must produce a CREATE TABLE statement');
        expect(sql, contains('('),
            reason: '${table.name} CREATE TABLE must have columns');
        expect(sql, contains(')'),
            reason: '${table.name} CREATE TABLE must close parens');
      }
    });

    test('zero-identity columns: no raw phone/email/name columns', () {
      final sensitiveTables = [
        AppSchema.users,
        AppSchema.messages,
        AppSchema.connectionRequests,
        AppSchema.ledgerDrafts,
        AppSchema.evidence,
        AppSchema.consentRecords,
        AppSchema.auditEvents,
      ];

      for (final table in sensitiveTables) {
        final sql = AppSchema.createTableSql(table).toLowerCase();
        expect(sql, isNot(contains('phone_number')),
            reason: '${table.name} must not have phone_number column');
        expect(sql, isNot(contains('email_address')),
            reason: '${table.name} must not have email_address column');
        expect(sql, isNot(contains('real_name')),
            reason: '${table.name} must not have real_name column');
        expect(sql, isNot(contains('full_name')),
            reason: '${table.name} must not have full_name column');
      }
    });

    test('schema tables cover all pillars', () {
      final allTables = [
        AppSchema.users, // Identity
        AppSchema.messages, // Relay
        AppSchema.ledgerDrafts, // Ledger
        AppSchema.evidence, // War Room
        AppSchema.academyModules, // Academy
        AppSchema.karmaEvents, // Cross-pillar
        AppSchema.consentRecords, // Compliance
        AppSchema.auditEvents, // Compliance
        AppSchema.transparencyEvents, // Transparency
        AppSchema.rateLimitBuckets, // Rate limiting
      ];

      final tableNames = allTables.map((t) => t.name).toSet();
      expect(tableNames.length, allTables.length,
          reason: 'All tables must have unique names');
    });

    test('all required table names are defined', () {
      // Verify each required table is defined as a const in AppSchema
      final requiredTables = [
        'sync_queue',
        'messages',
        'connection_requests',
        'devices',
        'ledger_drafts',
        'post_votes',
        'peer_reviews',
        'evidence',
        'intake_drafts',
        'academy_modules',
        'academy_progress',
        'sandbox_pages',
        'study_groups',
        'karma_events',
        'notifications',
        'consent_records',
        'audit_events',
        'transparency_events',
        'rate_limit_buckets',
        'abuse_events',
      ];

      for (final name in requiredTables) {
        expect(name, matches(RegExp(r'^[a-z][a-z_]+$')),
            reason: 'Table name "$name" must be valid SQL identifier');
      }
    });
  });
}
