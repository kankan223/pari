import 'ledger_vote.dart';

/// A locally-persisted Ledger vote (Task 7.5).
///
/// The durable local row behind a vote: the vote is written here FIRST
/// (offline-first), then its sealed envelope is queued for sync. On a cold
/// restart the device's vote direction on every post can be recovered.
///
/// SECURITY CONTRACT: carries ONLY the public post id + an aggregate
/// direction — no voter identity, no PII. The row lives inside the
/// SQLCipher-encrypted database; the queued copy is sealed by the queue
/// cipher.
class LedgerVoteRecord {
  final String postId;
  final LedgerVoteDirection direction;

  /// Last time this device changed its vote on [postId].
  final DateTime updatedAt;

  const LedgerVoteRecord({
    required this.postId,
    required this.direction,
    required this.updatedAt,
  });
}
