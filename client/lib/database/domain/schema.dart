/// A single column in a database table.
///
/// [sensitive] marks columns whose values must never exist in plaintext in
/// the database file. With SQLCipher the ENTIRE file is encrypted at rest,
/// but this flag additionally documents and enforces the security contract:
/// sensitive columns hold only ciphertext, hashes, or opaque payloads.
class DbColumn {
  final String name;

  /// SQLite type: TEXT, INTEGER, BLOB, etc.
  final String type;

  final bool primaryKey;
  final bool notNull;
  final bool unique;

  /// True when this column's values are sensitive and must be encrypted at
  /// rest (ciphertext, participant hashes, device keys, payloads).
  final bool sensitive;

  const DbColumn(
    this.name,
    this.type, {
    this.primaryKey = false,
    this.notNull = false,
    this.unique = false,
    this.sensitive = false,
  });

  String get definition {
    final parts = <String>['$name $type'];
    if (primaryKey) {
      parts.add('PRIMARY KEY');
    }
    if (notNull) {
      parts.add('NOT NULL');
    }
    if (unique) {
      parts.add('UNIQUE');
    }
    return parts.join(' ');
  }
}

/// A single database table definition.
class DbTable {
  final String name;
  final List<DbColumn> columns;

  const DbTable(this.name, this.columns);

  /// All columns flagged as sensitive (used by the security checkpoint).
  List<DbColumn> get sensitiveColumns =>
      columns.where((c) => c.sensitive).toList(growable: false);
}

/// The complete offline-first database schema (Task 3.1).
///
/// Entities defined by MASTER_PLAN.md:
/// - `users` (blind_hash_id, username, device_pubkey)
/// - `conversations` (id, participant_hash, encrypted_session_state)
/// - `messages` (id, conversation_id, ciphertext, delivered, expires_at)
/// - `connection_requests` (id, requester_hash, recipient_hash, status)
/// - `sync_queue` (id, operation_type, payload, status, retry_count)
class AppSchema {
  AppSchema._();

  static const DbTable users = DbTable('users', [
    DbColumn('blind_hash_id', 'TEXT',
        primaryKey: true, notNull: true, sensitive: true),
    DbColumn('username', 'TEXT', unique: true),
    DbColumn('device_pubkey', 'BLOB', notNull: true, sensitive: true),
  ]);

  static const DbTable conversations = DbTable('conversations', [
    DbColumn('id', 'TEXT', primaryKey: true, notNull: true),
    DbColumn('participant_hash', 'TEXT', notNull: true, sensitive: true),
    DbColumn('encrypted_session_state', 'BLOB', notNull: true, sensitive: true),
  ]);

  static const DbTable messages = DbTable('messages', [
    DbColumn('id', 'TEXT', primaryKey: true, notNull: true),
    DbColumn('conversation_id', 'TEXT', notNull: true),
    DbColumn('ciphertext', 'BLOB', notNull: true, sensitive: true),
    // Explicit sent/received side (Task 6.3) — stored as the wire name
    // ('sent'/'received'). Not sensitive: it is a delivery flag, not PII.
    DbColumn('direction', 'TEXT', notNull: true),
    DbColumn('delivered', 'INTEGER', notNull: true),
    DbColumn('expires_at', 'INTEGER'),
  ]);

  static const DbTable connectionRequests = DbTable('connection_requests', [
    DbColumn('id', 'TEXT', primaryKey: true, notNull: true),
    DbColumn('requester_hash', 'TEXT', notNull: true, sensitive: true),
    DbColumn('recipient_hash', 'TEXT', notNull: true, sensitive: true),
    DbColumn('status', 'TEXT', notNull: true),
  ]);

  static const DbTable syncQueue = DbTable('sync_queue', [
    DbColumn('id', 'TEXT', primaryKey: true, notNull: true),
    DbColumn('operation_type', 'TEXT', notNull: true),
    DbColumn('payload', 'BLOB', notNull: true, sensitive: true),
    DbColumn('status', 'TEXT', notNull: true),
    DbColumn('retry_count', 'INTEGER', notNull: true),
    DbColumn('created_at', 'INTEGER', notNull: true),
  ]);

  /// Locally linked devices (Task 6.5 multi-device pairing).
  ///
  /// `id` is the linked device's UUID v4; `blind_hash` is the OWNER of this
  /// local database (never a raw phone — the same 64-hex blind hash that
  /// keys every other table); `public_key` is the linked device's opaque
  /// public key material (base64url of the X3DH/identity public keys — never
  /// a private key); `paired_at` is the pairing timestamp; `revoked` marks a
  /// revoked device so a user can unlink it without deleting the row history.
  static const DbTable devices = DbTable('devices', [
    DbColumn('id', 'TEXT', primaryKey: true, notNull: true),
    DbColumn('blind_hash', 'TEXT', notNull: true, sensitive: true),
    DbColumn('public_key', 'BLOB', notNull: true, sensitive: true),
    DbColumn('paired_at', 'INTEGER', notNull: true),
    DbColumn('revoked', 'INTEGER', notNull: true),
  ]);

  /// Locally persisted Ledger drafts (Task 7.4 Post Creation & Queuing).
  ///
  /// A draft is written here FIRST (offline-first) and its sealed envelope
  /// is queued for sync. `pin_code` is the coarse civic scope (marked
  /// sensitive because it is the finest location signal the device holds —
  /// the SQLCipher file is encrypted at rest regardless). `category` is the
  /// category wire name; `headline`/`body` are public civic content.
  static const DbTable ledgerDrafts = DbTable('ledger_drafts', [
    DbColumn('id', 'TEXT', primaryKey: true, notNull: true),
    DbColumn('category', 'TEXT', notNull: true),
    DbColumn('pin_code', 'TEXT', notNull: true, sensitive: true),
    DbColumn('headline', 'TEXT', notNull: true),
    DbColumn('body', 'TEXT', notNull: true),
    DbColumn('created_at', 'INTEGER', notNull: true),
  ]);

  /// Locally recorded Ledger votes (Task 7.5 Voting System).
  ///
  /// One row per post the LOCAL device has voted on: `post_id` is the
  /// public post id, `direction` is the vote wire name ('up'/'down'),
  /// `updated_at` is the last change. The row is written FIRST (offline-
  /// first) so a vote survives a cold restart before its sealed envelope
  /// ever syncs. `direction` is a per-device aggregate preference, NOT PII
  /// — no identity column exists here by design (the voter is the device
  /// itself; the server tallies via the authenticated blind hash).
  static const DbTable postVotes = DbTable('post_votes', [
    DbColumn('post_id', 'TEXT', primaryKey: true, notNull: true),
    DbColumn('direction', 'TEXT', notNull: true),
    DbColumn('updated_at', 'INTEGER', notNull: true),
  ]);

  /// Locally recorded Peer Review decisions (Task 7.6 Peer Review Gate).
  ///
  /// One row per post the LOCAL device has reviewed: `post_id` is the
  /// public post id, `decision` is the review wire name
  /// ('approved'/'rejected'/'flagged'), `reviewed_at` is the last review.
  /// The row is written FIRST (offline-first) so a decision survives a
  /// cold restart before its sealed envelope ever syncs. NO identity
  /// column exists by design — the reviewer is the device itself and the
  /// server attributes the decision via the authenticated blind hash
  /// (SECURITY CHECKPOINT 7.6: reviewer identities blinded).
  static const DbTable peerReviews = DbTable('peer_reviews', [
    DbColumn('post_id', 'TEXT', primaryKey: true, notNull: true),
    DbColumn('decision', 'TEXT', notNull: true),
    DbColumn('reviewed_at', 'INTEGER', notNull: true),
  ]);

  /// Locally persisted War Room evidence (Task 8.2 Encrypted Evidence).
  ///
  /// One row per evidence item attached to a case. `sealed_file` is the
  /// AES-256-GCM(DEK) file ciphertext and `dek_envelope` is the serialized
  /// WRAPPED DEK — the plaintext DEK never touches the database. Only
  /// NON-sensitive metadata is stored (size, mime, timestamp, case stamp):
  /// there is NO filename, NO path, NO EXIF, NO identity column by design
  /// (a filename can embed sensitive context; the UI shows only the
  /// mime+size label). The SQLCipher file encrypts the whole row at rest
  /// regardless.
  static const DbTable evidence = DbTable('evidence', [
    DbColumn('id', 'TEXT', primaryKey: true, notNull: true),
    DbColumn('case_number', 'TEXT', notNull: true),
    DbColumn('sealed_file', 'BLOB', notNull: true, sensitive: true),
    DbColumn('dek_envelope', 'BLOB', notNull: true, sensitive: true),
    DbColumn('size_bytes', 'INTEGER', notNull: true),
    DbColumn('mime_type', 'TEXT', notNull: true),
    DbColumn('created_at', 'INTEGER', notNull: true),
  ]);

  /// Locally persisted paused War Room intake drafts (Task 8.7).
  ///
  /// One row per paused intake. `sealed_payload` is the AES-256-GCM SEALED
  /// `v:1` draft envelope (narrative = case content, never stored
  /// plaintext); `saved_at` is the pause timestamp (newest-first resume
  /// surface). ZERO identity columns — the same zero-identity intake
  /// contract as the case itself.
  static const DbTable intakeDrafts = DbTable('intake_drafts', [
    DbColumn('id', 'TEXT', primaryKey: true, notNull: true),
    DbColumn('sealed_payload', 'BLOB', notNull: true, sensitive: true),
    DbColumn('saved_at', 'INTEGER', notNull: true),
  ]);

  /// All tables, in creation order (foreign-key-safe).
  static const List<DbTable> tables = [
    users,
    conversations,
    messages,
    connectionRequests,
    syncQueue,
    devices,
    ledgerDrafts,
    postVotes,
    peerReviews,
    evidence,
    intakeDrafts,
  ];

  /// Current schema version — MUST be bumped when tables are added/changed.
  ///
  /// v2 (Task 5.2): `sync_queue.last_attempt_at` — retry gating timestamps.
  /// v3 (Task 6.3): `messages.direction` — explicit sent/received side.
  /// v4 (Task 6.5): `devices` — locally linked devices (multi-device
  /// pairing; QR-transfer of public key material only).
  /// v5 (Task 7.4): `ledger_drafts` — locally persisted Ledger drafts.
  /// v6 (Task 7.5): `post_votes` — locally recorded Ledger votes.
  /// v7 (Task 7.6): `peer_reviews` — locally recorded Peer Review decisions.
  /// v8 (Task 8.2): `evidence` — encrypted War Room evidence metadata +
  /// sealed file + wrapped DEK (no filename/identity by design).
  /// v9 (Task 8.7): `intake_drafts` — paused War Room intake drafts, sealed
  /// at rest (AES-256-GCM envelope; no identity columns).
  static const int currentVersion = 9;

  /// Builds the CREATE TABLE statement for [table].
  static String createTableSql(DbTable table) {
    final defs = table.columns.map((c) => c.definition).join(', ');
    return 'CREATE TABLE ${table.name} ($defs)';
  }

  /// All CREATE TABLE statements, in order.
  static List<String> createAllTableSql() =>
      tables.map(createTableSql).toList(growable: false);
}
