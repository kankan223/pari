import '../../geo/domain/explore_radius.dart';
import '../../ledger/domain/karma_weighted_score.dart';
import '../../ledger/domain/ledger_category.dart';
import '../../ledger/domain/ledger_post.dart';
import '../../ledger/domain/ledger_vote.dart';

/// UI-safe projection of a [LedgerPost].
///
/// SECURITY CHECKPOINT (Task 7.1): carries only the non-PII [authorHandle],
/// public civic content, and aggregate counts — never raw identity fields.
class LedgerPostSummary {
  final String id;
  final LedgerCategory category;
  final String pinCode;
  final String headline;
  final String body;
  final String authorHandle;
  final int voteCount;
  final int commentCount;

  /// The LOCAL device's vote on this post (Task 7.5) — drives the active
  /// state of the vote bar. A per-device aggregate, not identity.
  final LedgerVoteDirection myVote;

  /// The karma-weighted sub-linear score (Task 7.5) — the deterministic
  /// client-side projection rendered by the vote bar.
  final int karmaScore;

  final int verifiedReviewers;
  final LedgerPostStatus status;
  final DateTime createdAt;

  /// True when this post came from the dynamic-radius district fallback
  /// (Task 7.3) — the UI renders the NearbyBadge on it.
  final bool nearby;

  const LedgerPostSummary({
    required this.id,
    required this.category,
    required this.pinCode,
    required this.headline,
    required this.body,
    required this.authorHandle,
    required this.voteCount,
    required this.commentCount,
    required this.myVote,
    required this.karmaScore,
    required this.verifiedReviewers,
    required this.status,
    required this.createdAt,
    this.nearby = false,
  });

  factory LedgerPostSummary.from(LedgerPost post, {bool nearby = false}) =>
      LedgerPostSummary(
        id: post.id,
        category: post.category,
        pinCode: post.pinCode,
        headline: post.headline,
        body: post.body,
        authorHandle: post.authorHandle,
        voteCount: post.voteCount,
        commentCount: post.commentCount,
        myVote: post.myVote,
        // The local feed carries the net tally; the karma-weighted display
        // score is the deterministic sub-linear projection of it.
        karmaScore: KarmaWeightedScore.ofNet(post.voteCount),
        verifiedReviewers: post.verifiedReviewers,
        status: post.status,
        createdAt: post.createdAt,
        nearby: nearby,
      );
}

/// Lifecycle of the feed load.
enum LedgerFeedStatus { loading, loaded, error }

/// Immutable BLoC state for the Ledger feed (Task 7.1).
class LedgerFeedState {
  final LedgerFeedStatus status;

  /// The active pin-code scope (FR-L2: default feed is scoped to the user's
  /// pin code; cross-pin browsing is a later task).
  final String pinCode;

  /// Active category filter; null = All.
  final LedgerCategory? categoryFilter;

  /// The current edition number (masthead marker).
  final int edition;

  /// The visible post list (local-cache snapshot).
  final List<LedgerPostSummary> posts;

  /// Number of posts in Peer Review / Shadow Queue (teaser strip).
  final int pendingReviewCount;

  /// The active Explore Nearby radius (Task 7.3).
  final ExploreRadius radius;

  /// True when the feed actually expanded to include nearby posts.
  final bool isExpanded;

  /// Number of posts rendered from outside the exact pin.
  final int nearbyCount;

  const LedgerFeedState({
    this.status = LedgerFeedStatus.loading,
    this.pinCode = '',
    this.categoryFilter,
    this.edition = 0,
    this.posts = const [],
    this.pendingReviewCount = 0,
    this.radius = ExploreRadius.none,
    this.isExpanded = false,
    this.nearbyCount = 0,
  });

  bool get hasLoaded => status != LedgerFeedStatus.loading;

  LedgerFeedState copyWith({
    LedgerFeedStatus? status,
    String? pinCode,
    LedgerCategory? categoryFilter,
    bool clearCategory = false,
    int? edition,
    List<LedgerPostSummary>? posts,
    int? pendingReviewCount,
    ExploreRadius? radius,
    bool? isExpanded,
    int? nearbyCount,
  }) =>
      LedgerFeedState(
        status: status ?? this.status,
        pinCode: pinCode ?? this.pinCode,
        categoryFilter:
            clearCategory ? null : (categoryFilter ?? this.categoryFilter),
        edition: edition ?? this.edition,
        posts: posts ?? this.posts,
        pendingReviewCount: pendingReviewCount ?? this.pendingReviewCount,
        radius: radius ?? this.radius,
        isExpanded: isExpanded ?? this.isExpanded,
        nearbyCount: nearbyCount ?? this.nearbyCount,
      );
}
