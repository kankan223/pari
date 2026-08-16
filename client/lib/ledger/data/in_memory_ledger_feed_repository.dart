import '../domain/feed_scope.dart';
import '../domain/ledger_category.dart';
import '../domain/ledger_feed_repository.dart';
import '../domain/ledger_post.dart';
import '../domain/ledger_vote.dart';
import '../domain/peer_review.dart';
import '../domain/peer_review_gate.dart';

/// In-memory, LOCAL-CACHE-FIRST [LedgerFeedRepository] (data layer,
/// Task 7.1).
///
/// The feed renders from this local snapshot immediately — there is NO
/// network path here at all. The composition root seeds the local cache
/// (from a persisted snapshot or a future sync); this repository serves
/// reads and applies votes against the local copy, exactly the offline-first
/// contract the Ledger pillar requires.
///
/// SECURITY CHECKPOINT (Task 7.1): the file imports no http/WebSocket/dart:io
/// networking — the feed is local-first by construction (verified by the
/// 7.1 security checkpoint test).
class InMemoryLedgerFeedRepository implements LedgerFeedRepository {
  final Map<String, LedgerPost> _posts = {};
  final int _edition;

  InMemoryLedgerFeedRepository({
    List<LedgerPost> seed = const [],
    int edition = 412,
  }) : _edition = edition {
    for (final post in seed) {
      _posts[post.id] = post;
    }
  }

  /// Seeds (or replaces) the local cache. Used by the composition root and
  /// tests to populate the feed before first render.
  void seed(List<LedgerPost> posts) {
    for (final post in posts) {
      _posts[post.id] = post;
    }
  }

  @override
  Future<List<LedgerPost>> listPosts({
    required String pinCode,
    LedgerCategory? category,
  }) async {
    final matches = _posts.values.where((post) {
      if (post.pinCode != pinCode) {
        return false;
      }
      if (category != null && post.category != category) {
        return false;
      }
      return true;
    }).toList()
      // Newest first within status: published on top, then review/shadow
      // queue teasers at the bottom (DESIGN.md §7.2 ordering).
      ..sort(_feedOrder);
    return matches;
  }

  @override
  Future<FeedScopeResult> listScoped(FeedScope scope) async {
    final exact = _posts.values
        .where((p) =>
            p.pinCode == scope.pinCode &&
            (scope.category == null || p.category == scope.category))
        .toList();

    // Skill step 1: threshold check — fewer than `expansionThreshold` posts
    // in the last 7 days for the exact pin triggers the fallback query.
    final sevenDaysAgo = scope.now().subtract(const Duration(days: 7));
    final recentExact =
        exact.where((p) => !p.createdAt.isBefore(sevenDaysAgo)).length;

    final shouldExpand =
        scope.isExpanded && recentExact < scope.expansionThreshold;
    if (!shouldExpand) {
      return FeedScopeResult(
        posts: _ordered(exact),
        expanded: false,
        nearbyCount: 0,
        nearbyIds: const {},
      );
    }

    // Skill step 2: radius expansion — same-district / constituency fallback.
    final district = _districtOf(scope.pinCode);
    final nearby = <LedgerPost>[];
    if (district != null) {
      for (final post in _posts.values) {
        if (post.pinCode == scope.pinCode) {
          continue; // local posts already included
        }
        if (post.district == district &&
            (scope.category == null || post.category == scope.category)) {
          nearby.add(post);
        }
      }
    }

    // Skill step 4: seamless blending — ONE chronological feed, no
    // separate Local/Nearby sections.
    final blended = _ordered([...exact, ...nearby]);
    return FeedScopeResult(
      posts: blended,
      expanded: nearby.isNotEmpty,
      nearbyCount: nearby.length,
      nearbyIds: nearby.map((p) => p.id).toSet(),
    );
  }

  /// The district a pin belongs to: the district carried by the pin's own
  /// posts, or null when the cache has no district signal for it (in which
  /// case expansion is impossible — safe by default).
  String? _districtOf(String pinCode) {
    for (final post in _posts.values) {
      if (post.pinCode == pinCode && post.district != null) {
        return post.district;
      }
    }
    return null;
  }

  List<LedgerPost> _ordered(Iterable<LedgerPost> posts) => posts.toList()
    // Newest first within status: published on top, then review/shadow
    // queue teasers at the bottom (DESIGN.md §7.2 ordering).
    ..sort(_feedOrder);

  static int _feedOrder(LedgerPost a, LedgerPost b) {
    const published = LedgerPostStatus.published;
    if (a.status != published && b.status == published) return 1;
    if (a.status == published && b.status != published) return -1;
    return b.createdAt.compareTo(a.createdAt);
  }

  @override
  Future<LedgerPost?> getById(String id) async => _posts[id];

  @override
  Future<LedgerVoteDirection> vote(
      String id, LedgerVoteDirection direction) async {
    final post = _posts[id];
    if (post == null) {
      return LedgerVoteDirection.none;
    }
    final current = post.myVote;
    if (current == direction) {
      // Toggle OFF: the same direction again removes the device's vote.
      // NOTE: the net tally may go negative (downvotes exceed upvotes) — a
      // downvote on a 0-count post must be reversible, and the karma
      // display clamps negatives at the projection layer (KarmaWeightedScore
      // never renders a negative score).
      _posts[id] = post.copyWith(
        voteCount: post.voteCount - direction.delta,
        myVote: LedgerVoteDirection.none,
      );
      return LedgerVoteDirection.none;
    }
    // Switch / fresh vote: remove the old direction's contribution and add
    // the new one (none contributes 0).
    final net = post.voteCount - current.delta + direction.delta;
    _posts[id] = post.copyWith(
      voteCount: net,
      myVote: direction,
    );
    return direction;
  }

  @override
  Future<LedgerPostStatus> applyReview(
      String id, PeerReviewDecision decision) async {
    final post = _posts[id];
    if (post == null) {
      return LedgerPostStatus.peerReview;
    }
    // A published post is immutable — the gate has already passed; a late
    // approval must be a no-op (never drift the count past 3).
    if (post.status == LedgerPostStatus.published) {
      return LedgerPostStatus.published;
    }
    final approved = decision == PeerReviewDecision.approved;
    final nextCount =
        approved ? post.verifiedReviewers + 1 : post.verifiedReviewers;
    final nextStatus = PeerReviewGate.statusAfterReview(
      current: post.status,
      decision: decision,
      approvedCount: post.verifiedReviewers,
    );
    _posts[id] = post.copyWith(
      verifiedReviewers: nextCount,
      status: nextStatus,
    );
    return nextStatus;
  }

  @override
  Future<int> currentEdition() async => _edition;
}
