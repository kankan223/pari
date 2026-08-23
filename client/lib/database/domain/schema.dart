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
    // UTC milliseconds epoch when the message was sent (Task: timestamps).
    DbColumn('sent_at', 'INTEGER'),
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

  /// The Academy syllabus domains (Task 9.2 Syllabus Tree).
  ///
  /// One row per public course domain: `domain_id` is the stable slug,
  /// `title` is the public course-domain title, `locale` is the ISO 639-1
  /// tag. PUBLIC course content only — zero identity columns by design
  /// (the syllabus is served from this local cache, never the network).
  static const DbTable academyDomains = DbTable('academy_domains', [
    DbColumn('domain_id', 'TEXT', primaryKey: true, notNull: true),
    DbColumn('title', 'TEXT', notNull: true),
    DbColumn('locale', 'TEXT', notNull: true),
  ]);

  /// The Academy syllabus modules (Task 9.2 Syllabus Tree).
  ///
  /// One row per learning module: `module_id` is the validated UUID v4,
  /// `domain_id` is its parent domain slug, `title`/`duration_minutes`/
  /// `locale` are public course metadata, and `content_ref` is the OPAQUE
  /// non-PII media reference (never a raw URL, never a filename that could
  /// leak identity). ZERO identity columns.
  static const DbTable academyModules = DbTable('academy_modules', [
    DbColumn('module_id', 'TEXT', primaryKey: true, notNull: true),
    DbColumn('domain_id', 'TEXT', notNull: true),
    DbColumn('title', 'TEXT', notNull: true),
    DbColumn('duration_minutes', 'INTEGER', notNull: true),
    DbColumn('locale', 'TEXT', notNull: true),
    DbColumn('content_ref', 'TEXT', notNull: true),
  ]);

  /// The Academy progress ledger (Task 9.2 Syllabus Tree).
  ///
  /// One row per completed module: `module_id` is the validated UUID v4
  /// (row presence = completed). ZERO identity columns by design — the
  /// learner is the device itself; no phone/name/hash/timestamp ever
  /// attaches to a progress row (SECURITY CHECKPOINT 9.2: progress keys
  /// are UUID module ids only).
  static const DbTable academyProgress = DbTable('academy_progress', [
    DbColumn('module_id', 'TEXT', primaryKey: true, notNull: true),
  ]);

  /// The Academy Sandbox Wiki page ledger (Task 9.5 Sandbox Wiki System).
  ///
  /// One row per community study page. `page_id` is the validated UUID v4
  /// page id, `module_id` is the parent module's UUID v4 (the sandbox is
  /// module-scoped), `title` is the PUBLIC page title, `revision_count` is
  /// the append-only history length, `updated_at` the last revision. The
  /// body NEVER lives here — it lives in the sensitive `sandbox_revisions`
  /// table (community UGC may embed PII; the encrypted-partition contract
  /// holds for every wiki byte). ZERO identity columns by design.
  static const DbTable sandboxPages = DbTable('sandbox_pages', [
    DbColumn('page_id', 'TEXT', primaryKey: true, notNull: true),
    DbColumn('module_id', 'TEXT', notNull: true),
    DbColumn('title', 'TEXT', notNull: true),
    DbColumn('locale', 'TEXT', notNull: true),
    DbColumn('revision_count', 'INTEGER', notNull: true),
    DbColumn('updated_at', 'INTEGER', notNull: true),
  ]);

  /// The Academy Sandbox Wiki revision history (Task 9.5).
  ///
  /// One row per revision — append-only version control (PRD FR-A3:
  /// every revision diffable + revertible with attributed-but-pseudonymous
  /// authorship). `body_markdown` is community UGC flagged SENSITIVE (may
  /// embed PII — persisted only inside the encrypted partition and in the
  /// sealed sync envelope); `author_handle` is the deterministic `SA-####`
  /// pseudonymous handle, NEVER identity. ZERO identity columns.
  static const DbTable sandboxRevisions = DbTable('sandbox_revisions', [
    DbColumn('revision_id', 'TEXT', primaryKey: true, notNull: true),
    DbColumn('page_id', 'TEXT', notNull: true),
    DbColumn('body_markdown', 'TEXT', notNull: true, sensitive: true),
    DbColumn('author_handle', 'TEXT', notNull: true),
    DbColumn('created_at', 'INTEGER', notNull: true),
    DbColumn('prev_revision_id', 'TEXT'),
  ]);

  /// Locally cached Academy module content (Task 9.4 Offline Module
  /// Caching).
  ///
  /// One row per module with an offline-cache entry. `module_id` is the
  /// validated UUID v4 module id (the ONLY cache key — zero identity),
  /// `status` is the cache lifecycle wire name (queued/downloading/
  /// downloaded/failed), `total_bytes`/`cached_bytes` are the offline
  /// budget sizes, and `sealed_payload` is the AES-256-GCM SEALED content
  /// payload (ciphertext only — `sensitive`, the raw content never touches
  /// the row). The whole file is SQLCipher-encrypted at rest regardless
  /// (MASTER_PLAN §9.4 checkpoint: cached content lives in the encrypted
  /// partition). No identity, no raw URL, no filename column by design.
  static const DbTable moduleCache = DbTable('module_cache', [
    DbColumn('module_id', 'TEXT', primaryKey: true, notNull: true),
    DbColumn('status', 'TEXT', notNull: true),
    DbColumn('total_bytes', 'INTEGER', notNull: true),
    DbColumn('cached_bytes', 'INTEGER', notNull: true),
    DbColumn('downloaded_at', 'INTEGER'),
    DbColumn('sealed_payload', 'BLOB', sensitive: true),
    DbColumn('cached_at', 'INTEGER'),
  ]);

  /// Cross-pillar Academy study groups (Task 9.6 Study Group Matching).
  ///
  /// One row per study group. `group_id` is the validated UUID v4 group id,
  /// `module_id` is the anchor Academy module's UUID v4, `title` is the
  /// PUBLIC group title, `locale` the locale tag, `pin_code` is the coarse
  /// civic scope (sensitive — the same coarse signal as the Ledger feed;
  /// never a precise location), `topics` is the wire-serialized cross-pillar
  /// topic ref list, `capacity`/`participant_count` bound the group size and
  /// `created_at` stamps creation. ZERO identity columns by design —
  /// participants are identified ONLY by blinded `SG-####` handles living in
  /// `study_group_members` (SECURITY CHECKPOINT 9.6).
  static const DbTable studyGroups = DbTable('study_groups', [
    DbColumn('group_id', 'TEXT', primaryKey: true, notNull: true),
    DbColumn('module_id', 'TEXT', notNull: true),
    DbColumn('title', 'TEXT', notNull: true),
    DbColumn('locale', 'TEXT', notNull: true),
    DbColumn('pin_code', 'TEXT', notNull: true, sensitive: true),
    DbColumn('topics', 'TEXT', notNull: true),
    DbColumn('capacity', 'INTEGER', notNull: true),
    DbColumn('participant_count', 'INTEGER', notNull: true),
    DbColumn('created_at', 'INTEGER', notNull: true),
  ]);

  /// Local study group member rows (Task 9.6 Study Group Matching).
  ///
  /// One row per local membership. `member_id` is the validated UUID v4
  /// membership id, `group_id` the parent group's UUID v4, `member_handle`
  /// is the blinded deterministic `SG-####` handle (NEVER identity),
  /// `is_initiator` flags the creator and `joined_at` stamps the join.
  /// ZERO identity columns by design (SECURITY CHECKPOINT 9.6).
  static const DbTable studyGroupMembers = DbTable('study_group_members', [
    DbColumn('member_id', 'TEXT', primaryKey: true, notNull: true),
    DbColumn('group_id', 'TEXT', notNull: true),
    DbColumn('member_handle', 'TEXT', notNull: true),
    DbColumn('is_initiator', 'INTEGER', notNull: true),
    DbColumn('joined_at', 'INTEGER', notNull: true),
  ]);

  /// The append-only karma event ledger (Task 10.2 Civic Karma Engine).
  ///
  /// One row per karma event. `event_id` is the minted UUID v4 id (the
  /// wire Idempotency-Key), `seq` the monotonic chain position,
  /// `actor_hash` the validated 64-hex BLIND hash (sensitive — the ONLY
  /// actor identifier), `action` the fixed wire code, `delta`/`balance_after`
  /// the integer movement + running balance, `occurred_at` the timestamp,
  /// and `prev_hash`/`self_hash` the SHA-256 chain links for audit
  /// (SECURITY CHECKPOINT 10.2: append-only + auditable, zero identity).
  static const DbTable karmaEvents = DbTable('karma_events', [
    DbColumn('event_id', 'TEXT', primaryKey: true, notNull: true),
    DbColumn('seq', 'INTEGER', notNull: true),
    DbColumn('actor_hash', 'TEXT', notNull: true, sensitive: true),
    DbColumn('action', 'TEXT', notNull: true),
    DbColumn('delta', 'INTEGER', notNull: true),
    DbColumn('balance_after', 'INTEGER', notNull: true),
    DbColumn('occurred_at', 'INTEGER', notNull: true),
    DbColumn('prev_hash', 'TEXT', notNull: true),
    DbColumn('self_hash', 'TEXT', notNull: true),
  ]);

  /// The local notification store (Task 10.4 Notification System).
  ///
  /// One row per notification. `notification_id` is the UUID v4 id,
  /// `type` the fixed wire code, `title`/`body` public-label-only text,
  /// `created_at` the timestamp, `is_read` the read/unread flag.
  /// ZERO identity columns — no phones, no hashes, no tokens.
  static const DbTable notifications = DbTable('notifications', [
    DbColumn('notification_id', 'TEXT', primaryKey: true, notNull: true),
    DbColumn('type', 'TEXT', notNull: true),
    DbColumn('title', 'TEXT', notNull: true),
    DbColumn('body', 'TEXT', notNull: true),
    DbColumn('created_at', 'INTEGER', notNull: true),
    DbColumn('is_read', 'INTEGER', notNull: true),
  ]);

  /// The append-only transparency audit log (Task 10.5).
  ///
  /// One row per transparency event. `record_id` is the UUID v4 id,
  /// `seq` the monotonic chain position, `action` the fixed wire code,
  /// `summary` the public non-PII label, `pin_code` the civic scope,
  /// `occurred_at` the timestamp, `prev_hash`/`self_hash` the SHA-256
  /// chain links for audit (SECURITY CHECKPOINT 10.5: append-only +
  /// auditable, zero identity).
  static const DbTable transparencyEvents = DbTable('transparency_events', [
    DbColumn('record_id', 'TEXT', primaryKey: true, notNull: true),
    DbColumn('seq', 'INTEGER', notNull: true),
    DbColumn('action', 'TEXT', notNull: true),
    DbColumn('summary', 'TEXT', notNull: true),
    DbColumn('pin_code', 'TEXT', notNull: true),
    DbColumn('occurred_at', 'INTEGER', notNull: true),
    DbColumn('prev_hash', 'TEXT', notNull: true),
    DbColumn('self_hash', 'TEXT', notNull: true),
  ]);

  /// The DPDP consent tracking table (Task 11.1).
  ///
  /// One row per consent grant or withdrawal. `record_id` is the UUID v4 id,
  /// `type` the fixed consent wire code, `consent_version` the version the
  /// user agreed to, `granted` the boolean status, `timestamp` the event
  /// time, `text_hash` the SHA-256 of the consent document for tamper
  /// evidence. ZERO identity columns.
  static const DbTable consentRecords = DbTable('consent_records', [
    DbColumn('record_id', 'TEXT', primaryKey: true, notNull: true),
    DbColumn('type', 'TEXT', notNull: true),
    DbColumn('consent_version', 'TEXT', notNull: true),
    DbColumn('granted', 'INTEGER', notNull: true),
    DbColumn('timestamp', 'INTEGER', notNull: true),
    DbColumn('text_hash', 'TEXT', notNull: true),
  ]);

  /// Append-only, tamper-evident audit log (Task 11.2). `record_id` is
  /// UUID v4, `action` the fixed audit wire code, `summary` a public
  /// non-PII label, `occurred_at` the UTC timestamp, `seq` the monotonic
  /// chain position, `prev_hash`/`self_hash` the SHA-256 chain links.
  /// ZERO identity columns.
  static const DbTable auditEvents = DbTable('audit_events', [
    DbColumn('record_id', 'TEXT', primaryKey: true, notNull: true),
    DbColumn('seq', 'INTEGER', notNull: true),
    DbColumn('action', 'TEXT', notNull: true),
    DbColumn('summary', 'TEXT', notNull: true),
    DbColumn('occurred_at', 'INTEGER', notNull: true),
    DbColumn('prev_hash', 'TEXT', notNull: true),
    DbColumn('self_hash', 'TEXT', notNull: true),
  ]);

  /// Rate limiting buckets for request throttling (Task 11.3). Tracks
  /// per-policy request counts within sliding windows. ZERO identity columns.
  static const DbTable rateLimitBuckets = DbTable('rate_limit_buckets', [
    DbColumn('policy', 'TEXT', primaryKey: true, notNull: true),
    DbColumn('request_count', 'INTEGER', notNull: true),
    DbColumn('window_start', 'INTEGER', notNull: true),
    DbColumn('cooldown_active', 'INTEGER', notNull: true),
    DbColumn('cooldown_started_at', 'INTEGER'),
  ]);

  /// Abuse detection events for auditing (Task 11.3). Records when
  /// suspicious patterns were detected. ZERO identity columns.
  static const DbTable abuseEvents = DbTable('abuse_events', [
    DbColumn('event_id', 'TEXT', primaryKey: true, notNull: true),
    DbColumn('trigger_type', 'TEXT', notNull: true),
    DbColumn('severity', 'TEXT', notNull: true),
    DbColumn('detected_at', 'INTEGER', notNull: true),
    DbColumn('occurrence_count', 'INTEGER', notNull: true),
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
    academyDomains,
    academyModules,
    academyProgress,
    moduleCache,
    sandboxPages,
    sandboxRevisions,
    studyGroups,
    studyGroupMembers,
    karmaEvents,
    notifications,
    transparencyEvents,
    consentRecords,
    auditEvents,
    rateLimitBuckets,
    abuseEvents,
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
  /// v10 (Task 9.2): `academy_domains` / `academy_modules` /
  /// `academy_progress` — the Academy syllabus tree + progress ledger,
  /// served from the local cache (no identity columns).
  /// v11 (Task 9.4): `module_cache` — offline module cache entries
  /// (UUID module-id key + status + sizes + SEALED content payload).
  /// v12 (Task 9.5): `sandbox_pages` / `sandbox_revisions` — the Academy
  /// Sandbox Wiki (module-scoped community pages + append-only revision
  /// history with pseudonymous `SA-####` authorship; body_markdown is
  /// community UGC flagged sensitive).
  /// v13 (Task 9.6): `study_groups` / `study_group_members` — cross-pillar
  /// study group matching (anchor module UUID + public title + coarse pin
  /// scope + cross-pillar topic refs; blinded `SG-####` memberships).
  /// v14 (Task 10.2): `karma_events` — the append-only, auditable Civic
  /// Karma ledger (UUID event id + 64-hex blinded actor + fixed action +
  /// running balance + SHA-256 chain links; zero identity columns).
  /// v15 (Task 10.4): `notifications` — local notification store (UUID
  /// notification id + fixed type + public-label title/body + timestamp +
  /// is_read flag; zero identity columns).
  /// v16 (Task 10.5): `transparency_events` — append-only, auditable
  /// transparency log (UUID record id + fixed action + public summary +
  /// pin-code scope + timestamp + SHA-256 chain links; zero identity).
  /// v17 (Task 11.1): `consent_records` — DPDP consent tracking (UUID
  /// record id + fixed consent type + version + granted flag + timestamp +
  /// text hash; zero identity columns).
  /// v18 (Task 11.2): `audit_events` — append-only, tamper-evident audit
  /// log (UUID record id + fixed action + public summary + timestamp +
  /// SHA-256 chain links; zero identity columns).
  /// v19 (Task 11.3): `rate_limit_buckets` / `abuse_events` — rate
  /// limiting and abuse prevention tracking (per-policy request counts
  /// + sliding windows + abuse detection events; zero identity columns).
  static const int currentVersion = 20; // v20: messages.sent_at

  /// Builds the CREATE TABLE statement for [table].
  static String createTableSql(DbTable table) {
    final defs = table.columns.map((c) => c.definition).join(', ');
    return 'CREATE TABLE ${table.name} ($defs)';
  }

  /// All CREATE TABLE statements, in order.
  static List<String> createAllTableSql() =>
      tables.map(createTableSql).toList(growable: false);
}
