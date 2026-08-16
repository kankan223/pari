import 'feed_scope.dart';
import 'ledger_category.dart';
import 'ledger_post.dart';
import 'ledger_vote.dart';
import 'peer_review.dart';

/// Feed persistence boundary (port) for the Ledger (Task 7.1).
///
/// Repositories depend ONLY on this abstract interface. The production
/// implementation is local-cache-first (offline-first): the feed renders
/// from the local snapshot immediately and syncs through the queue — the
/// Ledger never blocks on the network (SECURITY CHECKPOINT Task 7.1).
///
/// SECURITY CONTRACT: entities carry only non-PII display handles, pin
/// codes, category enums, and public civic content — never raw identity.
abstract class LedgerFeedRepository {
  /// Returns the local feed snapshot for [pinCode], optionally filtered to
  /// [category]. Published posts first (chronological within status).
  Future<List<LedgerPost>> listPosts({
    required String pinCode,
    LedgerCategory? category,
  });

  /// Returns the DYNAMIC-RADIUS feed for [scope] (Task 7.3): when the
  /// scope's radius is expanded and the exact-pin feed is sparse (fewer
  /// than `expansionThreshold` posts in the last 7 days), the feed expands
  /// to same-district posts and flags them as nearby. Results are blended
  /// chronologically — no separate Local/Nearby sections.
  Future<FeedScopeResult> listScoped(FeedScope scope);

  /// Reads a single post, or null when absent.
  Future<LedgerPost?> getById(String id);

  /// Casts the local device's vote [direction] on the post with [id]
  /// (Task 7.5). Toggle semantics: voting the same direction again removes
  /// the vote; switching directions moves it. The post's net count and
  /// [LedgerPost.myVote] are updated locally.
  ///
  /// Returns the RESULTING [LedgerVoteDirection] after the toggle (none
  /// when the same direction was tapped again) — the caller enqueues that
  /// resolved state, so the sync envelope always carries the actual vote
  /// state, never the raw tap.
  Future<LedgerVoteDirection> vote(String id, LedgerVoteDirection direction);

  /// Applies a Peer Review [decision] to the post with [id] (Task 7.6):
  /// an `approved` decision increments [LedgerPost.verifiedReviewers] and
  /// publishes the post when the 3/3 consensus is reached; rejected /
  /// flagged decisions leave the status unchanged. Returns the post's new
  /// status (the consensus transition is resolved locally, offline-first).
  Future<LedgerPostStatus> applyReview(String id, PeerReviewDecision decision);

  /// The current edition number (the newspaper-of-record edition marker
  /// shown in the masthead, DESIGN.md §7.2). Derived locally.
  Future<int> currentEdition();
}
