import '../../geo/domain/explore_radius.dart';
import '../../ledger/domain/ledger_category.dart';
import '../../ledger/domain/ledger_vote.dart';
import 'ledger_feed_state.dart';

/// BLoC for the Ledger feed (Task 7.1).
///
/// Exposes a stream of [LedgerFeedState] derived from the local feed
/// repository (local-cache-first — no network in the read path). The UI
/// binds to [state] and never talks to the repository or network directly.
///
/// SECURITY CHECKPOINT (Task 7.1): state carries only UI-safe
/// [LedgerPostSummary]s — non-PII handles and public civic content.
abstract class LedgerFeedBloc {
  /// Stream of feed states.
  Stream<LedgerFeedState> get state;

  /// Loads the initial feed for [pinCode] from the local cache.
  Future<void> start(String pinCode);

  /// Re-reads the local cache for the current pin code.
  Future<void> refresh();

  /// Sets the active category filter (null clears to All).
  Future<void> selectCategory(LedgerCategory? category);

  /// Sets the Explore Nearby radius (Task 7.3) — refetches the feed, which
  /// expands to same-district posts when the local pin is sparse.
  Future<void> setRadius(ExploreRadius radius);

  /// Casts the local device's vote [direction] on the post with [postId]
  /// (Task 7.5). Toggle semantics: voting the same direction again removes
  /// the vote; switching directions moves it. The feed re-emits with the
  /// updated net count, active state, and karma-weighted score.
  Future<void> vote(String postId, LedgerVoteDirection direction);

  /// Releases resources.
  Future<void> close();
}
