import 'ledger_category.dart';

/// A locally-persisted Ledger draft (Task 7.4).
///
/// This is the durable local row behind the compose flow: the draft is
/// written here FIRST (offline-first), then its sealed envelope is queued
/// for sync. On a cold restart the draft can be recovered/listed locally
/// even before any sync has happened.
///
/// SECURITY CONTRACT: carries ONLY public civic fields (category enum, pin
/// code, headline, body) — no identity, no PII. The row lives inside the
/// SQLCipher-encrypted database; the queued copy is sealed by the queue
/// cipher.
class LedgerDraftRecord {
  final String id;
  final LedgerCategory category;
  final String pinCode;
  final String headline;
  final String body;
  final DateTime createdAt;

  const LedgerDraftRecord({
    required this.id,
    required this.category,
    required this.pinCode,
    required this.headline,
    required this.body,
    required this.createdAt,
  });
}
