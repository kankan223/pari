import 'ledger_vote.dart';
import 'ledger_vote_record.dart';

/// Persistence seam for Ledger votes (Task 7.5).
///
/// The UI votes through the BLoC; the BLoC hands a [LedgerVote] to this
/// port. The production implementation persists the vote locally FIRST
/// (offline-first) and enqueues the sealed envelope through the offline
/// sync queue; tests use in-memory implementations.
///
/// SECURITY CHECKPOINT (Task 7.5): votes are never persisted or logged in
/// a way that ties them to identity — the sink receives only the public
/// post id + aggregate direction and seals it at rest.
abstract class LedgerVoteSink {
  /// Records [vote] locally (offline-first). Returns the local record id.
  Future<String> save(LedgerVote vote);

  /// Every locally-recorded vote (recovery snapshot for cold starts).
  Future<List<LedgerVoteRecord>> localVotes();
}
