import '../domain/index_manager.dart';

/// All performance indexes defined for the Civic Commons schema (Task 12.2).
///
/// Each index targets a high-frequency query path identified by auditing
/// the 26 schema tables and their read/write patterns.
const List<DbIndex> performanceIndexes = [
  // --- sync_queue (Task 3.3/5.2): high-frequency status + retry queries ---
  DbIndex(
    name: 'idx_sync_queue_status',
    table: 'sync_queue',
    columns: ['status'],
  ),
  DbIndex(
    name: 'idx_sync_queue_status_created',
    table: 'sync_queue',
    columns: ['status', 'created_at'],
  ),
  DbIndex(
    name: 'idx_sync_queue_last_attempt',
    table: 'sync_queue',
    columns: ['last_attempt_at'],
    where: 'status IN (\'pending\', \'failed\')',
  ),

  // --- messages (Task 6.3): conversation-thread queries ---
  DbIndex(
    name: 'idx_messages_conversation',
    table: 'messages',
    columns: ['conversation_id'],
  ),
  DbIndex(
    name: 'idx_messages_conversation_direction',
    table: 'messages',
    columns: ['conversation_id', 'direction'],
  ),
  DbIndex(
    name: 'idx_messages_delivered',
    table: 'messages',
    columns: ['delivered'],
    where: 'delivered = 0',
  ),

  // --- connection_requests (Task 6.2): status + hash lookups ---
  DbIndex(
    name: 'idx_conn_requests_status',
    table: 'connection_requests',
    columns: ['status'],
  ),
  DbIndex(
    name: 'idx_conn_requests_recipient',
    table: 'connection_requests',
    columns: ['recipient_hash', 'status'],
  ),

  // --- devices (Task 6.5): owner lookups + revocation checks ---
  DbIndex(
    name: 'idx_devices_owner',
    table: 'devices',
    columns: ['blind_hash'],
  ),
  DbIndex(
    name: 'idx_devices_owner_active',
    table: 'devices',
    columns: ['blind_hash', 'revoked'],
    where: 'revoked = 0',
  ),

  // --- ledger_drafts (Task 7.4): chronological ordering ---
  DbIndex(
    name: 'idx_ledger_drafts_created',
    table: 'ledger_drafts',
    columns: ['created_at'],
  ),
  DbIndex(
    name: 'idx_ledger_drafts_category',
    table: 'ledger_drafts',
    columns: ['category', 'created_at'],
  ),

  // --- post_votes (Task 7.5): vote lookups ---
  DbIndex(
    name: 'idx_post_votes_direction',
    table: 'post_votes',
    columns: ['direction'],
  ),

  // --- evidence (Task 8.2): case-scoped queries ---
  DbIndex(
    name: 'idx_evidence_case',
    table: 'evidence',
    columns: ['case_number'],
  ),
  DbIndex(
    name: 'idx_evidence_case_created',
    table: 'evidence',
    columns: ['case_number', 'created_at'],
  ),

  // --- intake_drafts (Task 8.7): chronological ordering ---
  DbIndex(
    name: 'idx_intake_drafts_saved',
    table: 'intake_drafts',
    columns: ['saved_at'],
  ),

  // --- academy_modules (Task 9.2): domain-scoped queries ---
  DbIndex(
    name: 'idx_academy_modules_domain',
    table: 'academy_modules',
    columns: ['domain_id'],
  ),

  // --- module_cache (Task 9.4): status + cache lookups ---
  DbIndex(
    name: 'idx_module_cache_status',
    table: 'module_cache',
    columns: ['status'],
  ),
  DbIndex(
    name: 'idx_module_cache_status_cached',
    table: 'module_cache',
    columns: ['status', 'cached_at'],
  ),

  // --- sandbox_pages (Task 9.5): module-scoped queries ---
  DbIndex(
    name: 'idx_sandbox_pages_module',
    table: 'sandbox_pages',
    columns: ['module_id'],
  ),

  // --- sandbox_revisions (Task 9.5): page-scoped chronological ---
  DbIndex(
    name: 'idx_sandbox_revisions_page',
    table: 'sandbox_revisions',
    columns: ['page_id', 'created_at'],
  ),

  // --- study_groups (Task 9.6): pin-code + module matching ---
  DbIndex(
    name: 'idx_study_groups_pin',
    table: 'study_groups',
    columns: ['pin_code'],
  ),
  DbIndex(
    name: 'idx_study_groups_module',
    table: 'study_groups',
    columns: ['module_id'],
  ),
  DbIndex(
    name: 'idx_study_groups_pin_module',
    table: 'study_groups',
    columns: ['pin_code', 'module_id'],
  ),

  // --- study_group_members (Task 9.6): group-scoped queries ---
  DbIndex(
    name: 'idx_study_group_members_group',
    table: 'study_group_members',
    columns: ['group_id'],
  ),

  // --- karma_events (Task 10.2): append-only chain queries ---
  DbIndex(
    name: 'idx_karma_events_seq',
    table: 'karma_events',
    columns: ['seq'],
  ),
  DbIndex(
    name: 'idx_karma_events_actor',
    table: 'karma_events',
    columns: ['actor_hash'],
  ),
  DbIndex(
    name: 'idx_karma_events_action',
    table: 'karma_events',
    columns: ['action'],
  ),

  // --- notifications (Task 10.4): read/unread + type filtering ---
  DbIndex(
    name: 'idx_notifications_read',
    table: 'notifications',
    columns: ['is_read'],
  ),
  DbIndex(
    name: 'idx_notifications_type_read',
    table: 'notifications',
    columns: ['type', 'is_read'],
  ),
  DbIndex(
    name: 'idx_notifications_created',
    table: 'notifications',
    columns: ['created_at'],
  ),

  // --- transparency_events (Task 10.5): seq chain + pin-code scope ---
  DbIndex(
    name: 'idx_transparency_seq',
    table: 'transparency_events',
    columns: ['seq'],
  ),
  DbIndex(
    name: 'idx_transparency_pin',
    table: 'transparency_events',
    columns: ['pin_code'],
  ),

  // --- consent_records (Task 11.1): type-based queries ---
  DbIndex(
    name: 'idx_consent_type',
    table: 'consent_records',
    columns: ['type'],
  ),
  DbIndex(
    name: 'idx_consent_type_granted',
    table: 'consent_records',
    columns: ['type', 'granted'],
  ),

  // --- audit_events (Task 11.2): seq chain + action filtering ---
  DbIndex(
    name: 'idx_audit_seq',
    table: 'audit_events',
    columns: ['seq'],
  ),
  DbIndex(
    name: 'idx_audit_action',
    table: 'audit_events',
    columns: ['action'],
  ),

  // --- rate_limit_buckets (Task 11.3): policy lookups ---
  // PK is already the policy column, so no additional index needed.

  // --- abuse_events (Task 11.3): trigger + severity filtering ---
  DbIndex(
    name: 'idx_abuse_events_trigger',
    table: 'abuse_events',
    columns: ['trigger_type'],
  ),
  DbIndex(
    name: 'idx_abuse_events_severity',
    table: 'abuse_events',
    columns: ['severity'],
  ),
  DbIndex(
    name: 'idx_abuse_events_detected',
    table: 'abuse_events',
    columns: ['detected_at'],
  ),
];

/// In-memory implementation of [IndexManagerPort] for tests (Task 12.2).
///
/// Tracks which indexes have been created without an actual database.
class InMemoryIndexManager implements IndexManagerPort {
  final _createdIndexes = <String, DbIndex>{};

  @override
  List<DbIndex> get indexes => _createdIndexes.values.toList(growable: false);

  @override
  Future<void> createAllIndexes() async {
    for (final index in performanceIndexes) {
      _createdIndexes[index.name] = index;
    }
  }

  @override
  Future<void> dropAllIndexes() async {
    _createdIndexes.clear();
  }

  @override
  Future<void> createIndex(DbIndex index) async {
    _createdIndexes[index.name] = index;
  }

  @override
  Future<void> dropIndex(DbIndex index) async {
    _createdIndexes.remove(index.name);
  }

  @override
  Future<bool> indexExists(String name) async {
    return _createdIndexes.containsKey(name);
  }
}
