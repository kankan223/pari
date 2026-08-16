import '../../ledger/domain/peer_review.dart';
import 'ledger_review_state.dart';

/// BLoC for the Peer Review Gate queue (Task 7.6).
///
/// Exposes a stream of [LedgerReviewState] derived from the local feed
/// repository + review decisions. The UI binds to [state] and never talks
/// to the repository or network directly.
///
/// SECURITY CHECKPOINT (Task 7.6): state carries only non-PII projections
/// and blinded reviewer handles.
abstract class LedgerReviewBloc {
  /// Stream of review queue states.
  Stream<LedgerReviewState> get state;

  /// Loads the review queue for [pinCode] from the local cache.
  Future<void> start(String pinCode);

  /// Casts a Peer Review [decision] on the post with [postId] (approve /
  /// reject / flag). Approvals count toward the 3/3 consensus; the post
  /// publishes locally when reached. The decision is persisted offline-first
  /// and queued as a sealed envelope.
  Future<void> submit(String postId, PeerReviewDecision decision);

  /// Releases resources.
  Future<void> close();
}
