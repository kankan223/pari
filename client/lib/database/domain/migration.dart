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
    const Migration(
      version: 5,
      description: 'Add ledger_drafts table for locally persisted Ledger '
          'drafts (Task 7.4)',
      upStatements: [
        // Drafts carry ONLY public civic fields + the coarse pin scope
        // (sensitive column) inside the encrypted database.
        'CREATE TABLE ledger_drafts (id TEXT PRIMARY KEY NOT NULL, '
            'category TEXT NOT NULL, pin_code TEXT NOT NULL, '
            'headline TEXT NOT NULL, body TEXT NOT NULL, '
            'created_at INTEGER NOT NULL)',
      ],
      downStatements: [
        'DROP TABLE ledger_drafts',
      ],
    ),
    const Migration(
      version: 6,
      description: 'Add post_votes table for locally recorded Ledger votes '
          '(Task 7.5)',
      upStatements: [
        // Votes carry ONLY the public post id + an aggregate direction
        // (no identity column by design) inside the encrypted database.
        'CREATE TABLE post_votes (post_id TEXT PRIMARY KEY NOT NULL, '
            'direction TEXT NOT NULL, updated_at INTEGER NOT NULL)',
      ],
      downStatements: [
        'DROP TABLE post_votes',
      ],
    ),
    const Migration(
      version: 7,
      description: 'Add peer_reviews table for locally recorded Peer Review '
          'decisions (Task 7.6)',
      upStatements: [
        // Decisions carry ONLY the public post id + a decision code
        // (no identity column by design) inside the encrypted database.
        'CREATE TABLE peer_reviews (post_id TEXT PRIMARY KEY NOT NULL, '
            'decision TEXT NOT NULL, reviewed_at INTEGER NOT NULL)',
      ],
      downStatements: [
        'DROP TABLE peer_reviews',
      ],
    ),
    const Migration(
      version: 8,
      description: 'Add evidence table for encrypted War Room evidence '
          '(Task 8.2)',
      upStatements: [
        // Evidence rows carry ONLY non-sensitive metadata (size, mime,
        // timestamp, case stamp) + the sealed file + WRAPPED DEK blobs
        // inside the encrypted database. NO filename, NO identity column.
        'CREATE TABLE evidence (id TEXT PRIMARY KEY NOT NULL, '
            'case_number TEXT NOT NULL, sealed_file BLOB NOT NULL, '
            'dek_envelope BLOB NOT NULL, size_bytes INTEGER NOT NULL, '
            'mime_type TEXT NOT NULL, created_at INTEGER NOT NULL)',
      ],
      downStatements: [
        'DROP TABLE evidence',
      ],
    ),
    const Migration(
      version: 9,
      description: 'Add intake_drafts table for paused War Room intake '
          'drafts (Task 8.7)',
      upStatements: [
        // Draft rows carry ONLY the id + the AES-256-GCM SEALED envelope
        // (sensitive BLOB) + the pause timestamp inside the encrypted
        // database. NO plaintext narrative, NO identity column.
        'CREATE TABLE intake_drafts (id TEXT PRIMARY KEY NOT NULL, '
            'sealed_payload BLOB NOT NULL, saved_at INTEGER NOT NULL)',
      ],
      downStatements: [
        'DROP TABLE intake_drafts',
      ],
    ),
    const Migration(
      version: 10,
      description: 'Add Academy syllabus tree + progress tables (Task 9.2)',
      upStatements: [
        // The Academy syllabus is PUBLIC course content served from the
        // local cache — zero identity columns. Modules carry validated
        // UUID v4 ids + opaque non-PII content refs. Progress rows hold
        // ONLY the UUID module id (presence = completed).
        'CREATE TABLE academy_domains (domain_id TEXT PRIMARY KEY NOT NULL, '
            'title TEXT NOT NULL, locale TEXT NOT NULL)',
        'CREATE TABLE academy_modules (module_id TEXT PRIMARY KEY NOT NULL, '
            'domain_id TEXT NOT NULL, title TEXT NOT NULL, '
            'duration_minutes INTEGER NOT NULL, locale TEXT NOT NULL, '
            'content_ref TEXT NOT NULL)',
        'CREATE TABLE academy_progress (module_id TEXT PRIMARY KEY NOT NULL)',
      ],
      downStatements: [
        'DROP TABLE academy_progress',
        'DROP TABLE academy_modules',
        'DROP TABLE academy_domains',
      ],
    ),
    const Migration(
      version: 11,
      description: 'Add module_cache table for offline Academy module '
          'caching (Task 9.4)',
      upStatements: [
        // Cache rows carry ONLY the UUID module-id key + a status wire name
        // + sizes + the AES-256-GCM SEALED content payload (sensitive BLOB)
        // inside the encrypted database. NO plaintext content, NO identity
        // column.
        'CREATE TABLE module_cache (module_id TEXT PRIMARY KEY NOT NULL, '
            'status TEXT NOT NULL, total_bytes INTEGER NOT NULL, '
            'cached_bytes INTEGER NOT NULL, downloaded_at INTEGER, '
            'sealed_payload BLOB, cached_at INTEGER)',
      ],
      downStatements: [
        'DROP TABLE module_cache',
      ],
    ),
    const Migration(
      version: 12,
      description: 'Add Sandbox Wiki tables for the Academy community '
          'study notes (Task 9.5)',
      upStatements: [
        // Page rows carry ONLY UUID v4 ids + a public title + locale + the
        // revision count + a timestamp — ZERO identity columns, NO body.
        'CREATE TABLE sandbox_pages (page_id TEXT PRIMARY KEY NOT NULL, '
            'module_id TEXT NOT NULL, title TEXT NOT NULL, '
            'locale TEXT NOT NULL, revision_count INTEGER NOT NULL, '
            'updated_at INTEGER NOT NULL)',
        // Revision rows carry the Markdown body (community UGC — sensitive,
        // may embed PII, persisted only inside the encrypted partition) + the
        // deterministic SA-#### pseudonymous author handle. ZERO identity
        // columns.
        'CREATE TABLE sandbox_revisions (revision_id TEXT PRIMARY KEY NOT '
            'NULL, page_id TEXT NOT NULL, body_markdown TEXT NOT NULL, '
            'author_handle TEXT NOT NULL, created_at INTEGER NOT NULL, '
            'prev_revision_id TEXT)',
      ],
      downStatements: [
        'DROP TABLE sandbox_revisions',
        'DROP TABLE sandbox_pages',
      ],
    ),
    const Migration(
      version: 13,
      description: 'Add cross-pillar study group tables for the Academy '
          '(Task 9.6)',
      upStatements: [
        // Group rows carry ONLY a UUID v4 group id + the anchor module UUID
        // + a public title + locale + the coarse civic pin scope (sensitive)
        // + wire-serialized cross-pillar topic refs + capacity/count +
        // timestamp — ZERO identity columns, no participant handles.
        'CREATE TABLE study_groups (group_id TEXT PRIMARY KEY NOT NULL, '
            'module_id TEXT NOT NULL, title TEXT NOT NULL, '
            'locale TEXT NOT NULL, pin_code TEXT NOT NULL, '
            'topics TEXT NOT NULL, capacity INTEGER NOT NULL, '
            'participant_count INTEGER NOT NULL, '
            'created_at INTEGER NOT NULL)',
        // Member rows carry ONLY the UUID v4 membership id + the parent
        // group id + the blinded SG-#### handle + initiator flag + join
        // timestamp — ZERO identity columns.
        'CREATE TABLE study_group_members (member_id TEXT PRIMARY KEY NOT '
            'NULL, group_id TEXT NOT NULL, member_handle TEXT NOT NULL, '
            'is_initiator INTEGER NOT NULL, joined_at INTEGER NOT NULL)',
      ],
      downStatements: [
        'DROP TABLE study_group_members',
        'DROP TABLE study_groups',
      ],
    ),
    const Migration(
      version: 14,
      description: 'Add the append-only karma event ledger for the Civic '
          'Karma Engine (Task 10.2)',
      upStatements: [
        // Append-only, auditable karma events — event_id is the minted
        // UUID v4 (wire Idempotency-Key), actor_hash the validated 64-hex
        // BLIND hash (sensitive), action the fixed wire code, delta + the
        // running balance_after, occurred_at the timestamp, and the
        // SHA-256 prev_hash/self_hash chain links — ZERO identity columns.
        'CREATE TABLE karma_events (event_id TEXT PRIMARY KEY NOT NULL, '
            'seq INTEGER NOT NULL, actor_hash TEXT NOT NULL, '
            'action TEXT NOT NULL, delta INTEGER NOT NULL, '
            'balance_after INTEGER NOT NULL, '
            'occurred_at INTEGER NOT NULL, prev_hash TEXT NOT NULL, '
            'self_hash TEXT NOT NULL)',
      ],
      downStatements: [
        'DROP TABLE karma_events',
      ],
    ),
    const Migration(
      version: 15,
      description: 'Add the local notification store for the Notification '
          'System (Task 10.4)',
      upStatements: [
        // Local notification store — UUID notification id, fixed type wire
        // code, public-label title/body text, timestamp, is_read flag.
        // ZERO identity columns — no phones, no hashes, no tokens.
        'CREATE TABLE notifications (notification_id TEXT PRIMARY KEY '
            'NOT NULL, type TEXT NOT NULL, title TEXT NOT NULL, '
            'body TEXT NOT NULL, created_at INTEGER NOT NULL, '
            'is_read INTEGER NOT NULL)',
      ],
      downStatements: [
        'DROP TABLE notifications',
      ],
    ),
    const Migration(
      version: 16,
      description: 'Add the append-only transparency audit log for the '
          'Transparency Log (Task 10.5)',
      upStatements: [
        // Append-only, auditable transparency events — record_id is the
        // UUID v4 id, action the fixed wire code, summary the public
        // non-PII label, pin_code the civic scope, occurred_at the
        // timestamp, prev_hash/self_hash the SHA-256 chain links.
        // ZERO identity columns.
        'CREATE TABLE transparency_events (record_id TEXT PRIMARY KEY '
            'NOT NULL, seq INTEGER NOT NULL, action TEXT NOT NULL, '
            'summary TEXT NOT NULL, pin_code TEXT NOT NULL, '
            'occurred_at INTEGER NOT NULL, prev_hash TEXT NOT NULL, '
            'self_hash TEXT NOT NULL)',
      ],
      downStatements: [
        'DROP TABLE transparency_events',
      ],
    ),
    const Migration(
      version: 17,
      description: 'Add DPDP consent tracking table for the Consent '
          'Implementation (Task 11.1)',
      upStatements: [
        // DPDP consent records — UUID record id, fixed consent type,
        // version string, granted flag, timestamp, text hash for tamper
        // evidence. ZERO identity columns.
        'CREATE TABLE consent_records (record_id TEXT PRIMARY KEY '
            'NOT NULL, type TEXT NOT NULL, consent_version TEXT NOT NULL, '
            'granted INTEGER NOT NULL, timestamp INTEGER NOT NULL, '
            'text_hash TEXT NOT NULL)',
      ],
      downStatements: [
        'DROP TABLE consent_records',
      ],
    ),
    const Migration(
      version: 18,
      description: 'Add audit_events for tamper-evident audit logging '
          '(Task 11.2)',
      upStatements: [
        // Append-only audit log — UUID record id, fixed action,
        // public summary, timestamp, monotonic seq, SHA-256 chain
        // links. ZERO identity columns.
        'CREATE TABLE audit_events (record_id TEXT PRIMARY KEY '
            'NOT NULL, seq INTEGER NOT NULL, action TEXT NOT NULL, '
            'summary TEXT NOT NULL, occurred_at INTEGER NOT NULL, '
            'prev_hash TEXT NOT NULL, self_hash TEXT NOT NULL)',
      ],
      downStatements: [
        'DROP TABLE audit_events',
      ],
    ),
    const Migration(
      version: 19,
      description: 'Add rate_limit_buckets and abuse_events for Rate Limiting '
          '& Abuse Prevention (Task 11.3)',
      upStatements: [
        // Rate limiting buckets — per-policy request counts within
        // sliding windows. ZERO identity columns.
        'CREATE TABLE rate_limit_buckets (policy TEXT PRIMARY KEY '
            'NOT NULL, request_count INTEGER NOT NULL, '
            'window_start INTEGER NOT NULL, '
            'cooldown_active INTEGER NOT NULL, '
            'cooldown_started_at INTEGER)',
        // Abuse detection events — fixed trigger types + severity +
        // timestamps. ZERO identity columns.
        'CREATE TABLE abuse_events (event_id TEXT PRIMARY KEY '
            'NOT NULL, trigger_type TEXT NOT NULL, '
            'severity TEXT NOT NULL, detected_at INTEGER NOT NULL, '
            'occurrence_count INTEGER NOT NULL)',
      ],
      downStatements: [
        'DROP TABLE abuse_events',
        'DROP TABLE rate_limit_buckets',
      ],
    ),
    const Migration(
      version: 20,
      description: 'Add messages.sent_at for chat timestamps',
      upStatements: [
        'ALTER TABLE messages ADD COLUMN sent_at INTEGER',
      ],
      downStatements: [
        // SQLite does not support DROP COLUMN before 3.35;
        // acceptable data loss on downgrade for this non-critical column.
      ],
    ),
    const Migration(
      version: 21,
      description: 'Add file_attachments for encrypted file/image sharing',
      upStatements: [
        'CREATE TABLE file_attachments (id TEXT PRIMARY KEY NOT NULL, '
            'conversation_id TEXT NOT NULL, message_id TEXT NOT NULL, '
            'display_name TEXT NOT NULL, mime_type TEXT NOT NULL, '
            'original_size INTEGER NOT NULL, '
            'encrypted_bytes BLOB NOT NULL, '
            'thumbnail_bytes BLOB, created_at INTEGER NOT NULL)',
      ],
      downStatements: [
        'DROP TABLE file_attachments',
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
