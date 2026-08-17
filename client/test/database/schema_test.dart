import 'package:flutter_test/flutter_test.dart';
import 'package:civic_commons/database/domain/schema.dart';

void main() {
  group('AppSchema - entity definitions', () {
    test('defines all nineteen tables', () {
      final names = AppSchema.tables.map((t) => t.name).toSet();

      expect(
        names,
        equals({
          'users',
          'conversations',
          'messages',
          'connection_requests',
          'sync_queue',
          'devices',
          'ledger_drafts',
          'post_votes',
          'peer_reviews',
          'evidence',
          'intake_drafts',
          'academy_domains',
          'academy_modules',
          'academy_progress',
          'module_cache',
          'sandbox_pages',
          'sandbox_revisions',
          'study_groups',
          'study_group_members',
        }),
      );
    });

    test(
        'module_cache carries UUID key + status + sizes + SEALED payload '
        '(9.4)', () {
      final columns = AppSchema.moduleCache.columns.map((c) => c.name).toList();

      expect(columns, [
        'module_id',
        'status',
        'total_bytes',
        'cached_bytes',
        'downloaded_at',
        'sealed_payload',
        'cached_at',
      ]);
      // ZERO identity columns — the ONLY key is the validated UUID module
      // id; no user/device/phone/hash-shaped column can exist.
      final all = columns.join(',').toLowerCase();
      expect(all, isNot(contains('hash')));
      expect(all, isNot(contains('phone')));
      expect(all, isNot(contains('email')));
      expect(all, isNot(contains('user')));
      expect(all, isNot(contains('device')));
      expect(all, isNot(contains('author')));
      expect(all, isNot(contains('name')));
      // The sealed content payload is flagged sensitive (ciphertext only —
      // cached content lives in the encrypted partition, MASTER_PLAN §9.4).
      final sealed = AppSchema.moduleCache.columns
          .firstWhere((c) => c.name == 'sealed_payload');
      expect(sealed.sensitive, isTrue);
      expect(sealed.type, 'BLOB');
    });

    test('intake_drafts table carries id + SEALED payload + timestamp (8.7)',
        () {
      final columns =
          AppSchema.intakeDrafts.columns.map((c) => c.name).toList();

      expect(columns, ['id', 'sealed_payload', 'saved_at']);
      // SECURITY CHECKPOINT 8.7: the draft row holds ONLY ciphertext — no
      // plaintext narrative, no identity column.
      final all = columns.join(',').toLowerCase();
      expect(all, isNot(contains('narrative')));
      expect(all, isNot(contains('hash')));
      expect(all, isNot(contains('phone')));
      expect(all, isNot(contains('author')));
      final sealed = AppSchema.intakeDrafts.columns
          .firstWhere((c) => c.name == 'sealed_payload');
      expect(sealed.sensitive, isTrue,
          reason: 'the sealed draft envelope is opaque ciphertext');
    });

    test('evidence table carries ONLY metadata + ciphertext (8.2)', () {
      final columns = AppSchema.evidence.columns.map((c) => c.name).toList();

      expect(columns, [
        'id',
        'case_number',
        'sealed_file',
        'dek_envelope',
        'size_bytes',
        'mime_type',
        'created_at'
      ]);
      // SECURITY CHECKPOINT 8.2: NO filename / path / identity column.
      final all = columns.join(',').toLowerCase();
      expect(all, isNot(contains('name')));
      expect(all, isNot(contains('path')));
      expect(all, isNot(contains('hash')));
      expect(all, isNot(contains('phone')));
      expect(all, isNot(contains('author')));
      // The ciphertext blobs are flagged sensitive (opaque by construction).
      final sensitive = AppSchema.evidence.sensitiveColumns.map((c) => c.name);
      expect(sensitive, containsAll(['sealed_file', 'dek_envelope']));
    });

    test('study_groups table carries UUID keys + coarse pin + topics (9.6)',
        () {
      final columns = AppSchema.studyGroups.columns.map((c) => c.name).toList();

      expect(columns, [
        'group_id',
        'module_id',
        'title',
        'locale',
        'pin_code',
        'topics',
        'capacity',
        'participant_count',
        'created_at',
      ]);
      // SECURITY CHECKPOINT 9.6: ZERO identity columns — only UUID keys,
      // public title, coarse pin scope, topic refs, sizes + timestamp.
      final all = columns.join(',').toLowerCase();
      expect(all, isNot(contains('hash')));
      expect(all, isNot(contains('phone')));
      expect(all, isNot(contains('email')));
      expect(all, isNot(contains('user')));
      expect(all, isNot(contains('author')));
      expect(all, isNot(contains('handle')));
      // The coarse civic pin scope is flagged sensitive (never precise).
      final pin =
          AppSchema.studyGroups.columns.firstWhere((c) => c.name == 'pin_code');
      expect(pin.sensitive, isTrue);
    });

    test('study_group_members table carries ONLY blinded handles (9.6)', () {
      final columns =
          AppSchema.studyGroupMembers.columns.map((c) => c.name).toList();

      expect(columns, [
        'member_id',
        'group_id',
        'member_handle',
        'is_initiator',
        'joined_at',
      ]);
      // The member handle is the blinded SG-#### pseudonym — the ONLY
      // identity-shaped column that exists by design is the blinded handle
      // itself; no phone/name/hash/email can appear.
      final all = columns.join(',').toLowerCase();
      expect(all, isNot(contains('phone')));
      expect(all, isNot(contains('email')));
      expect(all, isNot(contains('hash')));
      expect(all, isNot(contains('name')));
    });

    test('peer_reviews table carries post + decision + timestamp (7.6)', () {
      final columns = AppSchema.peerReviews.columns.map((c) => c.name).toList();

      expect(columns, ['post_id', 'decision', 'reviewed_at']);
      // No identity column by design — a review row is a per-device action.
      final all = columns.join(',').toLowerCase();
      expect(all, isNot(contains('hash')));
      expect(all, isNot(contains('phone')));
      expect(all, isNot(contains('author')));
      expect(all, isNot(contains('reviewer')));
    });

    test('post_votes table carries post + direction + timestamp (7.5)', () {
      final columns = AppSchema.postVotes.columns.map((c) => c.name).toList();

      expect(columns, ['post_id', 'direction', 'updated_at']);
      // No identity column by design — a vote row is a per-device aggregate.
      final all = columns.join(',').toLowerCase();
      expect(all, isNot(contains('hash')));
      expect(all, isNot(contains('phone')));
      expect(all, isNot(contains('author')));
    });

    test('ledger_drafts table carries civic fields + coarse pin scope (7.4)',
        () {
      final columns =
          AppSchema.ledgerDrafts.columns.map((c) => c.name).toList();

      expect(
        columns,
        containsAll(
            ['id', 'category', 'pin_code', 'headline', 'body', 'created_at']),
      );
      final pin = AppSchema.ledgerDrafts.columns
          .firstWhere((c) => c.name == 'pin_code');
      expect(pin.sensitive, isTrue,
          reason:
              'pin scope is the finest location signal — flagged sensitive');
      // Drafts must never carry identity columns.
      final all = columns.join(',').toLowerCase();
      expect(all, isNot(contains('hash')));
      expect(all, isNot(contains('phone')));
      expect(all, isNot(contains('author')));
    });

    test('academy_domains carries PUBLIC course content only (9.2)', () {
      final columns =
          AppSchema.academyDomains.columns.map((c) => c.name).toList();

      expect(columns, ['domain_id', 'title', 'locale']);
      final all = columns.join(',').toLowerCase();
      // ZERO identity columns by design — public course content.
      expect(all, isNot(contains('hash')));
      expect(all, isNot(contains('phone')));
      expect(all, isNot(contains('email')));
      expect(all, isNot(contains('user')));
      expect(all, isNot(contains('device')));
      // No sensitive columns — nothing here is PII (not even flagged).
      expect(AppSchema.academyDomains.sensitiveColumns, isEmpty);
    });

    test('academy_modules carries validated UUID ids + opaque refs (9.2)', () {
      final columns =
          AppSchema.academyModules.columns.map((c) => c.name).toList();

      expect(columns, [
        'module_id',
        'domain_id',
        'title',
        'duration_minutes',
        'locale',
        'content_ref',
      ]);
      final all = columns.join(',').toLowerCase();
      // ZERO identity columns — no user/device/author/name-shaped column.
      expect(all, isNot(contains('hash')));
      expect(all, isNot(contains('phone')));
      expect(all, isNot(contains('email')));
      expect(all, isNot(contains('user')));
      expect(all, isNot(contains('device')));
      expect(all, isNot(contains('author')));
      expect(AppSchema.academyModules.sensitiveColumns, isEmpty);
    });

    test('sandbox_pages carries page UUID + public content only (9.5)', () {
      final columns =
          AppSchema.sandboxPages.columns.map((c) => c.name).toList();

      expect(columns, [
        'page_id',
        'module_id',
        'title',
        'locale',
        'revision_count',
        'updated_at',
      ]);
      final all = columns.join(',').toLowerCase();
      // ZERO identity columns — the body lives in the revisions table; the
      // page row is public content + UUID keys + a timestamp.
      expect(all, isNot(contains('hash')));
      expect(all, isNot(contains('phone')));
      expect(all, isNot(contains('email')));
      expect(all, isNot(contains('user')));
      expect(all, isNot(contains('device')));
      expect(all, isNot(contains('author')));
      expect(AppSchema.sandboxPages.sensitiveColumns, isEmpty);
    });

    test('sandbox_revisions carries body (SENSITIVE) + SA handle (9.5)', () {
      final columns =
          AppSchema.sandboxRevisions.columns.map((c) => c.name).toList();

      expect(columns, [
        'revision_id',
        'page_id',
        'body_markdown',
        'author_handle',
        'created_at',
        'prev_revision_id',
      ]);
      // The Markdown body is community UGC flagged SENSITIVE — persisted
      // only inside the encrypted partition (may embed PII).
      final body = AppSchema.sandboxRevisions.columns
          .firstWhere((c) => c.name == 'body_markdown');
      expect(body.sensitive, isTrue);
      // ZERO identity columns — the author is the deterministic SA-####
      // pseudonymous handle, never a raw identity.
      final all = columns.join(',').toLowerCase();
      expect(all, isNot(contains('phone')));
      expect(all, isNot(contains('email')));
      expect(all, isNot(contains('user')));
      expect(all, isNot(contains('device')));
    });

    test('academy_progress carries ONLY the UUID module id (9.2)', () {
      final columns =
          AppSchema.academyProgress.columns.map((c) => c.name).toList();

      expect(columns, ['module_id']);
      // ZERO identity columns — presence of the row = completed, nothing
      // else attaches to it.
      final all = columns.join(',').toLowerCase();
      expect(all, isNot(contains('hash')));
      expect(all, isNot(contains('phone')));
      expect(all, isNot(contains('email')));
      expect(all, isNot(contains('user')));
      expect(all, isNot(contains('device')));
      expect(all, isNot(contains('timestamp')));
      expect(all, isNot(contains('at')));
      expect(AppSchema.academyProgress.sensitiveColumns, isEmpty);
    });

    test('users table has blind_hash_id, username, device_pubkey', () {
      final columns = AppSchema.users.columns.map((c) => c.name).toList();

      expect(
          columns, containsAll(['blind_hash_id', 'username', 'device_pubkey']));
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
        containsAll(
            ['ciphertext', 'delivered', 'expires_at', 'conversation_id']),
      );
    });

    test('messages table has the explicit direction column (Task 6.3)', () {
      final direction =
          AppSchema.messages.columns.firstWhere((c) => c.name == 'direction');

      expect(direction.type, 'TEXT');
      expect(direction.notNull, isTrue);
      expect(direction.sensitive, isFalse,
          reason: 'direction is a delivery flag, not PII');
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

      expect(statements, hasLength(AppSchema.tables.length));
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
      expect(sensitiveNames, contains('devices.blind_hash'));
      expect(sensitiveNames, contains('devices.public_key'));
      expect(sensitiveNames, contains('ledger_drafts.pin_code'));
      expect(sensitiveNames, contains('intake_drafts.sealed_payload'));
      expect(sensitiveNames, contains('module_cache.sealed_payload'));
    });

    test('devices table has blind-hash + public-key columns only', () {
      final columns = AppSchema.devices.columns.map((c) => c.name).toList();

      expect(
          columns,
          containsAll(
              ['id', 'blind_hash', 'public_key', 'paired_at', 'revoked']));
      // No phone/username-shaped column can ever exist in the devices table.
      expect(columns.join(',').toLowerCase(), isNot(contains('phone')));
      expect(columns.join(',').toLowerCase(), isNot(contains('username')));
    });

    test(
        'academy syllabus + progress tables declare zero sensitive columns '
        '(nothing to encrypt is PII)', () {
      // SECURITY CHECKPOINT 9.2: the syllabus + progress are PUBLIC course
      // content / UUID keys — no ciphertext, no hashes, no PII. The
      // sensitive-column registry must stay empty for all three tables.
      expect(AppSchema.academyDomains.sensitiveColumns, isEmpty);
      expect(AppSchema.academyModules.sensitiveColumns, isEmpty);
      expect(AppSchema.academyProgress.sensitiveColumns, isEmpty);
      // SECURITY CHECKPOINT 9.4: the module cache is the ONE academy table
      // that DOES hold sensitive bytes — the SEALED content payload (only
      // ciphertext, never plaintext).
      expect(
        AppSchema.moduleCache.sensitiveColumns.map((c) => c.name),
        ['sealed_payload'],
      );
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
