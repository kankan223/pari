/// Locally-persisted Sandbox page row (Task 9.5).
///
/// Persisted inside the encrypted SQLCipher database (`sandbox_pages`,
/// schema v12). The page row is the aggregate metadata — the body lives in
/// the revision history.
///
/// SECURITY CHECKPOINT (Task 9.5): the row carries ONLY validated UUID v4
/// ids, a public title, a locale tag, a revision count and a timestamp —
/// zero identity columns, no body (the body is UGC and lives in the
/// sensitive `sandbox_revisions` table).
class SandboxPageRecord {
  final String pageId;
  final String moduleId;
  final String title;
  final String locale;
  final int revisionCount;
  final DateTime updatedAt;

  const SandboxPageRecord({
    required this.pageId,
    required this.moduleId,
    required this.title,
    required this.locale,
    required this.revisionCount,
    required this.updatedAt,
  });
}

/// A locally-persisted Sandbox revision row (Task 9.5).
///
/// Persisted inside the encrypted SQLCipher database (`sandbox_revisions`,
/// schema v12) — the append-only version history.
///
/// SECURITY CHECKPOINT (Task 9.5): the body_markdown column is flagged
/// SENSITIVE (community UGC may embed PII — the encrypted-partition
/// contract holds for every persisted wiki byte); the author is the
/// deterministic `SA-####` pseudonymous handle, never identity.
class SandboxRevisionRecord {
  final String revisionId;
  final String pageId;
  final String bodyMarkdown;
  final String authorHandle;
  final DateTime createdAt;
  final String? prevRevisionId;

  const SandboxRevisionRecord({
    required this.revisionId,
    required this.pageId,
    required this.bodyMarkdown,
    required this.authorHandle,
    required this.createdAt,
    this.prevRevisionId,
  });
}
