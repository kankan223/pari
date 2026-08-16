import '../../geo/domain/explore_radius.dart';
import 'ledger_category.dart';
import 'ledger_post.dart';

/// A feed query scope (Task 7.3 Dynamic Radius UI).
///
/// [radius] is a COARSE, user-chosen civic scope — it never encodes or
/// requires device coordinates (SECURITY CHECKPOINT Task 7.2/7.3). When
/// the radius is expanded and the local pin feed is sparse, the repository
/// falls back to same-district posts and flags them as nearby.
class FeedScope {
  final String pinCode;
  final ExploreRadius radius;

  /// Optional category filter applied to BOTH the exact-pin posts and the
  /// expanded nearby posts.
  final LedgerCategory? category;

  /// Injectable clock for the 7-day recency window (testable).
  final DateTime Function() now;

  /// The dynamic-radius threshold: when the local pin has FEWER than this
  /// many posts in the last 7 days, the feed expands to the district
  /// (skill: dynamic-radius-ui step 1).
  final int expansionThreshold;

  const FeedScope({
    required this.pinCode,
    this.radius = ExploreRadius.none,
    this.category,
    this.now = _systemNow,
    this.expansionThreshold = 5,
  });

  bool get isExpanded => radius.isExpanded;

  static DateTime _systemNow() => DateTime.now();
}

/// The result of a dynamic-radius feed query.
///
/// [posts] is the blended, chronologically-ordered feed (local posts +
/// expanded nearby posts — NO separate sections, skill step 4). A post's
/// `nearby` flag (carried by [LedgerPostSummary.nearby]) tells the UI to
/// render the NearbyBadge (skill step 3).
class FeedScopeResult {
  final List<LedgerPost> posts;

  /// True when the query actually expanded beyond the exact pin.
  final bool expanded;

  /// Number of posts that came from outside the exact pin.
  final int nearbyCount;

  /// The ids of the posts that came from outside the exact pin (the UI
  /// renders the NearbyBadge on exactly these). Computed by the repository.
  final Set<String> nearbyIds;

  const FeedScopeResult({
    required this.posts,
    required this.expanded,
    required this.nearbyCount,
    required this.nearbyIds,
  });
}
