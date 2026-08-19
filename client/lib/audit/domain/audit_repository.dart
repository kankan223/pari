import 'audit_record.dart';

/// Repository port for the Audit Logging System (Task 11.2).
///
/// All operations are local-first and offline-safe. The repository is
/// APPEND-ONLY — there is no update or delete API. [verifyIntegrity]
/// recomputes the entire SHA-256 chain and reports any tampering.
///
/// SECURITY CHECKPOINT (11.2): the repository carries only
/// [AuditRecord] objects with public-label summaries and fixed
/// action types — no identity, no PII, no tokens.
abstract class AuditRepository {
  /// Returns all records, ordered by sequence (oldest first).
  Future<List<AuditRecord>> getAll();

  /// Returns the total record count.
  Future<int> getCount();

  /// Appends a new record. The caller must provide a UUID v4 [recordId]
  /// and pre-computed [prevHash]/[selfHash]. The repository validates
  /// that seq is exactly next-in-seq.
  Future<void> append(AuditRecord record);

  /// Recomputes the SHA-256 chain and returns true if every link is valid.
  /// Returns false if any record was tampered, reordered, or removed.
  Future<bool> verifyIntegrity();
}
