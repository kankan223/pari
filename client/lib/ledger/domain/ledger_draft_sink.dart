import 'ledger_category.dart';

/// A locally-composed Ledger draft, ready for persistence (Task 7.1).
///
/// SECURITY CONTRACT: the draft carries ONLY public civic fields — no
/// identity, no PII. Persistence seals the draft with the offline-first
/// queue cipher at rest.
class LedgerDraft {
  final LedgerCategory category;
  final String pinCode;
  final String headline;
  final String body;

  const LedgerDraft({
    required this.category,
    required this.pinCode,
    required this.headline,
    required this.body,
  });
}

/// Persistence seam for composed Ledger drafts (Task 7.1).
///
/// The UI composes through the BLoC; the BLoC validates and hands the
/// [LedgerDraft] to this port. The production implementation enqueues the
/// sealed draft through the offline-first sync queue (later Phase 7 tasks);
/// tests and the initial foundation use an in-memory implementation.
///
/// SECURITY CHECKPOINT (Task 7.1): drafts are never persisted or logged in
/// plaintext — the sink receives the civic content and seals it at rest.
abstract class LedgerDraftSink {
  /// Persists [draft] locally (offline-first). Returns the local draft id.
  Future<String> save(LedgerDraft draft);
}
