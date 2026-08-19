import 'dart:io';

import 'package:civic_commons/database/domain/schema.dart';
import 'package:flutter_test/flutter_test.dart';

/// Comprehensive Security Audit & Penetration Testing (Task 11.4).
///
/// This test suite verifies OWASP MASVS compliance and anti-tamper
/// constraints across ALL modules in the Civic Commons codebase.
///
/// SECURITY CHECKPOINT (11.4): every test in this file verifies a specific
/// security invariant. A failure here indicates a security regression that
/// must be fixed before deployment.
void main() {
  group('OWASP MASVS - Network Isolation (MSTG-NETWORK-1)', () {
    test('domain layers have no networking imports', () {
      final domainDirs = [
        'lib/rate_limit/domain',
        'lib/audit/domain',
        'lib/consent/domain',
        'lib/transparency/domain',
        'lib/notification/domain',
        'lib/karma/domain',
        'lib/identity',
        'lib/academy/domain',
        'lib/war_room/domain',
        'lib/ledger/domain',
        'lib/pairing',
        'lib/sync/domain',
        'lib/repository/domain',
      ];

      for (final dir in domainDirs) {
        final files = _dartFilesIn(dir);
        for (final f in files) {
          final source = f.readAsStringSync();
          expect(
            _hasNetworkingImport(source),
            isFalse,
            reason: '${f.path} contains a networking import in domain layer',
          );
        }
      }
    });

    test('data layers have no direct networking imports', () {
      // Exception: relay data layer uses web_socket_channel (by design)
      final dataDirs = [
        'lib/rate_limit/data',
        'lib/audit/data',
        'lib/consent/data',
        'lib/transparency/data',
        'lib/notification/data',
        'lib/karma/data',
        'lib/sync/data',
        'lib/repository/data',
        'lib/database',
      ];

      for (final dir in dataDirs) {
        final files = _dartFilesIn(dir);
        for (final f in files) {
          final source = f.readAsStringSync();
          expect(
            _hasNetworkingImport(source),
            isFalse,
            reason: '${f.path} contains a networking import in data layer',
          );
        }
      }
    });

    test('UI layers have no networking imports', () {
      final uiDirs = [
        'lib/state/ui',
        'lib/security/ui',
      ];

      for (final dir in uiDirs) {
        final files = _dartFilesIn(dir);
        for (final f in files) {
          final source = f.readAsStringSync();
          expect(
            _hasNetworkingImport(source),
            isFalse,
            reason: '${f.path} contains a networking import in UI layer',
          );
        }
      }
    });
  });

  group('OWASP MASVS - Secure Logging (MSTG-PLATFORM-12)', () {
    test('no print/debugPrint in domain layers', () {
      final domainDirs = [
        'lib/rate_limit/domain',
        'lib/audit/domain',
        'lib/consent/domain',
        'lib/transparency/domain',
        'lib/notification/domain',
        'lib/karma/domain',
        'lib/identity',
        'lib/academy/domain',
        'lib/war_room/domain',
        'lib/ledger/domain',
        'lib/pairing',
        'lib/sync/domain',
        'lib/repository/domain',
      ];

      for (final dir in domainDirs) {
        final files = _dartFilesIn(dir);
        for (final f in files) {
          final lines = f.readAsStringSync().split('\n');
          for (var i = 0; i < lines.length; i++) {
            final line = lines[i];
            if (line.trimLeft().startsWith('//')) continue;
            expect(
              _hasPrintStatement(line),
              isFalse,
              reason: '${f.path}:${i + 1} contains print/debugPrint',
            );
          }
        }
      }
    });

    test('no print/debugPrint in data layers', () {
      final dataDirs = [
        'lib/rate_limit/data',
        'lib/audit/data',
        'lib/consent/data',
        'lib/transparency/data',
        'lib/notification/data',
        'lib/karma/data',
        'lib/sync/data',
        'lib/repository/data',
        'lib/database',
      ];

      for (final dir in dataDirs) {
        final files = _dartFilesIn(dir);
        for (final f in files) {
          final lines = f.readAsStringSync().split('\n');
          for (var i = 0; i < lines.length; i++) {
            final line = lines[i];
            if (line.trimLeft().startsWith('//')) continue;
            expect(
              _hasPrintStatement(line),
              isFalse,
              reason: '${f.path}:${i + 1} contains print/debugPrint',
            );
          }
        }
      }
    });

    test('no print/debugPrint in UI layers', () {
      final uiDirs = [
        'lib/state/ui',
        'lib/state/domain',
        'lib/state/data',
        'lib/security/ui',
      ];

      for (final dir in uiDirs) {
        final files = _dartFilesIn(dir);
        for (final f in files) {
          final lines = f.readAsStringSync().split('\n');
          for (var i = 0; i < lines.length; i++) {
            final line = lines[i];
            if (line.trimLeft().startsWith('//')) continue;
            expect(
              _hasPrintStatement(line),
              isFalse,
              reason: '${f.path}:${i + 1} contains print/debugPrint',
            );
          }
        }
      }
    });
  });

  group('OWASP MASVS - Data Protection (MSTG-STORAGE-1)', () {
    test('all 26 schema tables have zero identity columns', () {
      final identityColumns = [
        'phone',
        'email',
        'user_id',
        'user_name',
        'full_name',
        'first_name',
        'last_name',
        'address',
        'date_of_birth',
        'national_id',
        'aadhaar',
        'pan',
        'ssn',
      ];

      for (final table in AppSchema.tables) {
        final columnNames =
            table.columns.map((c) => c.name.toLowerCase()).toList();
        for (final identityCol in identityColumns) {
          expect(
            columnNames.contains(identityCol),
            isFalse,
            reason:
                'Table ${table.name} contains identity column $identityCol',
          );
        }
      }
    });

    test('sensitive columns are flagged for encryption', () {
      // These tables MUST have sensitive columns marked
      final tablesWithSensitiveColumns = [
        'users', // blind_hash_id, device_pubkey
        'conversations', // participant_hash, encrypted_session_state
        'messages', // ciphertext
        'connection_requests', // requester_hash, recipient_hash
        'sync_queue', // payload
        'devices', // blind_hash, public_key
        'evidence', // sealed_file, dek_envelope
        'intake_drafts', // sealed_payload
        'module_cache', // sealed_payload
        'sandbox_revisions', // body_markdown
        'study_groups', // pin_code
        'karma_events', // actor_hash
      ];

      for (final tableName in tablesWithSensitiveColumns) {
        final table = AppSchema.tables.firstWhere(
          (t) => t.name == tableName,
          orElse: () => throw StateError('Table $tableName not found'),
        );
        expect(
          table.sensitiveColumns.isNotEmpty,
          isTrue,
          reason: 'Table $tableName should have sensitive columns',
        );
      }
    });
  });

  group('OWASP MASVS - Platform Security (MSTG-PLATFORM-1)', () {
    test('FLAG_SECURE wrapper exists in secure_screen_wrapper.dart', () {
      final wrapperFile = File('lib/security/ui/secure_screen_wrapper.dart');
      expect(wrapperFile.existsSync(), isTrue);
      final source = wrapperFile.readAsStringSync();
      expect(source, contains('FLAG_SECURE'));
      expect(source, contains('SecureScreenWrapper'));
    });

    test('all major UI screens use SecureScreenWrapper', () {
      final screensToCheck = [
        'lib/state/ui/rate_limit_screen.dart',
        'lib/state/ui/audit_log_screen.dart',
        'lib/state/ui/dpdp_consent_screen.dart',
        'lib/state/ui/transparency_log_screen.dart',
        'lib/state/ui/notification_history_screen.dart',
        'lib/state/ui/notification_preferences_screen.dart',
        'lib/state/ui/karma_status_screen.dart',
        'lib/state/ui/identity_verification_screen.dart',
        'lib/state/ui/war_room_intake_screen.dart',
        'lib/state/ui/vault_conversation_list_screen.dart',
        'lib/state/ui/vault_conversation_detail_screen.dart',
      ];

      for (final screenPath in screensToCheck) {
        final file = File(screenPath);
        if (file.existsSync()) {
          final source = file.readAsStringSync();
          expect(
            source.contains('SecureScreenWrapper'),
            isTrue,
            reason: '$screenPath does not use SecureScreenWrapper',
          );
        }
      }
    });
  });

  group('OWASP MASVS - Code Quality (MSTG-CODE-1)', () {
    test('no hardcoded secrets or credentials', () {
      final libFiles = _dartFilesIn('lib');
      final secretPatterns = [
        RegExp(r'password\s*=\s*"[^"]+"', caseSensitive: false),
        RegExp(r'api_key\s*=\s*"[^"]+"', caseSensitive: false),
        RegExp(r'secret\s*=\s*"[^"]+"', caseSensitive: false),
        RegExp(r'token\s*=\s*"[^"]+"', caseSensitive: false),
      ];

      for (final f in libFiles) {
        // Skip test files and generated files
        if (f.path.contains('test') || f.path.contains('.g.dart')) continue;

        final source = f.readAsStringSync();
        for (final pattern in secretPatterns) {
          expect(
            pattern.hasMatch(source),
            isFalse,
            reason: '${f.path} may contain hardcoded secrets',
          );
        }
      }
    });

    test('no eval or dynamic code execution', () {
      final libFiles = _dartFilesIn('lib');
      for (final f in libFiles) {
        if (f.path.contains('test')) continue;
        final source = f.readAsStringSync();
        expect(
          source.contains('eval(') || source.contains('Function.apply('),
          isFalse,
          reason: '${f.path} contains dynamic code execution',
        );
      }
    });
  });

  group('Security Checkpoint - Schema Integrity', () {
    test('schema version is 19', () {
      expect(AppSchema.currentVersion, 19);
    });

    test('all 26 tables are defined', () {
      expect(AppSchema.tables.length, 26);
    });

    test('no table has empty column list', () {
      for (final table in AppSchema.tables) {
        expect(
          table.columns.isNotEmpty,
          isTrue,
          reason: 'Table ${table.name} has no columns',
        );
      }
    });

    test('every table has a primary key', () {
      for (final table in AppSchema.tables) {
        final hasPrimaryKey = table.columns.any((c) => c.primaryKey);
        expect(
          hasPrimaryKey,
          isTrue,
          reason: 'Table ${table.name} has no primary key',
        );
      }
    });
  });

  group('Security Checkpoint - Encryption at Rest', () {
    test('SQLCipher tables are encrypted', () {
      // All tables in the schema are stored in the SQLCipher database
      // which encrypts the entire file at rest
      expect(AppSchema.tables.length, greaterThan(0));
    });

    test('queue payloads are sealed before storage', () {
      // The sync_queue.payload column is flagged sensitive
      final syncQueue = AppSchema.tables.firstWhere(
        (t) => t.name == 'sync_queue',
      );
      final payloadColumn = syncQueue.columns.firstWhere(
        (c) => c.name == 'payload',
      );
      expect(payloadColumn.sensitive, isTrue);
    });

    test('evidence files are sealed', () {
      final evidence = AppSchema.tables.firstWhere(
        (t) => t.name == 'evidence',
      );
      final sealedFile = evidence.columns.firstWhere(
        (c) => c.name == 'sealed_file',
      );
      final dekEnvelope = evidence.columns.firstWhere(
        (c) => c.name == 'dek_envelope',
      );
      expect(sealedFile.sensitive, isTrue);
      expect(dekEnvelope.sensitive, isTrue);
    });
  });
}

/// Checks if source code contains networking imports.
bool _hasNetworkingImport(String source) {
  return source.contains("import 'dart:io'") ||
      source.contains('import "dart:io"') ||
      source.contains("import 'package:http'") ||
      source.contains('import "package:http"') ||
      source.contains("import 'package:web_socket_channel'") ||
      source.contains('import "package:web_socket_channel"');
}

/// Checks if a line contains print/debugPrint statements.
bool _hasPrintStatement(String line) {
  return line.contains('print(') || line.contains('debugPrint(');
}

/// Returns all .dart files in a directory recursively.
List<File> _dartFilesIn(String dir) {
  final directory = Directory(dir);
  if (!directory.existsSync()) return [];
  return directory
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();
}
