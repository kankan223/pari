import 'package:flutter_test/flutter_test.dart';
import 'package:civic_commons/database/domain/schema.dart';

void main() {
  group('AppSchema - entity definitions', () {
    test('defines all five core tables', () {
      final names = AppSchema.tables.map((t) => t.name).toSet();

      expect(
        names,
        equals({
          'users',
          'conversations',
          'messages',
          'connection_requests',
          'sync_queue',
        }),
      );
    });

    test('users table has blind_hash_id, username, device_pubkey', () {
      final columns = AppSchema.users.columns.map((c) => c.name).toList();

      expect(columns, containsAll(['blind_hash_id', 'username', 'device_pubkey']));
      expect(
        AppSchema.users.columns
            .firstWhere((c) => c.name == 'blind_hash_id')
            .primaryKey,
        isTrue,
      );
    });

    test('messages table has ciphertext and delivered/expires_at', () {
      final columns = AppSchema.messages.columns.map((c) => c.name).toList();

      expect(
        columns,
        containsAll(['ciphertext', 'delivered', 'expires_at', 'conversation_id']),
      );
    });

    test('sync_queue table has payload, status, retry_count', () {
      final columns = AppSchema.syncQueue.columns.map((c) => c.name).toList();

      expect(
        columns,
        containsAll(['operation_type', 'payload', 'status', 'retry_count']),
      );
    });
  });

  group('AppSchema - SQL generation', () {
    test('createAllTableSql produces one CREATE TABLE per table', () {
      final statements = AppSchema.createAllTableSql();

      expect(statements, hasLength(5));
      expect(statements.first, startsWith('CREATE TABLE users ('));
      expect(
        statements.join('\n'),
        isNot(contains('DROP TABLE')),
      );
    });

    test('CREATE TABLE SQL includes sensitive column names', () {
      final usersSql = AppSchema.createTableSql(AppSchema.users);

      expect(usersSql, contains('blind_hash_id TEXT PRIMARY KEY NOT NULL'));
      expect(usersSql, contains('device_pubkey BLOB NOT NULL'));
    });
  });

  group('AppSchema - SECURITY CHECKPOINT (sensitive columns)', () {
    test('ciphertext, hashes, and payloads are flagged sensitive', () {
      final sensitiveNames = <String>[
        for (final table in AppSchema.tables)
          ...table.sensitiveColumns.map((c) => '${table.name}.${c.name}'),
      ];

      expect(sensitiveNames, contains('messages.ciphertext'));
      expect(sensitiveNames, contains('conversations.participant_hash'));
      expect(sensitiveNames, contains('conversations.encrypted_session_state'));
      expect(sensitiveNames, contains('connection_requests.requester_hash'));
      expect(sensitiveNames, contains('connection_requests.recipient_hash'));
      expect(sensitiveNames, contains('users.device_pubkey'));
      expect(sensitiveNames, contains('users.blind_hash_id'));
      expect(sensitiveNames, contains('sync_queue.payload'));
    });

    test('sensitive columns hold only BLOB/TEXT ciphertext or hashes', () {
      for (final table in AppSchema.tables) {
        for (final column in table.sensitiveColumns) {
          expect(
            ['BLOB', 'TEXT'],
            contains(column.type),
            reason:
                'Sensitive column ${table.name}.${column.name} must be BLOB '
                'or TEXT (opaque ciphertext/hash), never a plaintext-friendly '
                'type',
          );
        }
      }
    });
  });
}
