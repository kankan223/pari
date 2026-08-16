import 'dart:async';

import '../../geo/domain/explore_radius.dart';
import '../../ledger/domain/feed_scope.dart';
import '../../ledger/domain/ledger_category.dart';
import '../../ledger/domain/ledger_feed_repository.dart';
import '../../ledger/domain/ledger_post.dart';
import '../../ledger/domain/ledger_vote.dart';
import '../../ledger/domain/ledger_vote_sink.dart';
import '../domain/ledger_feed_bloc.dart';
import '../domain/ledger_feed_state.dart';

/// Local-cache-backed [LedgerFeedBloc] (data layer, Task 7.1).
///
/// Reads the feed ONLY from the injected [LedgerFeedRepository] — the
/// offline-first contract. Never touches the network.
class LocalLedgerFeedBloc implements LedgerFeedBloc {
  final LedgerFeedRepository _repository;

  /// Optional vote persistence seam (Task 7.5): when injected, every vote is
  /// recorded offline-first AND queued as a sealed envelope by the sink.
  /// When absent (foundation/unit tests) votes update the local cache only.
  final LedgerVoteSink? _votes;

  final StreamController<LedgerFeedState> _controller =
      StreamController<LedgerFeedState>.broadcast();

  String _pinCode = '';
  LedgerCategory? _categoryFilter;
  ExploreRadius _radius = ExploreRadius.none;

  /// Monotonic snapshot sequence — a stale pull can never overwrite a
  /// fresher one (codebase convention, cf. Task 6.2).
  int _seq = 0;

  LocalLedgerFeedBloc({
    required LedgerFeedRepository repository,
    LedgerVoteSink? votes,
  })  : _repository = repository,
        _votes = votes;

  @override
  Stream<LedgerFeedState> get state => _controller.stream;

  @override
  Future<void> start(String pinCode) async {
    _pinCode = pinCode;
    await _emit();
  }

  @override
  Future<void> refresh() async {
    await _emit();
  }

  @override
  Future<void> selectCategory(LedgerCategory? category) async {
    _categoryFilter = category;
    await _emit();
  }

  @override
  Future<void> setRadius(ExploreRadius radius) async {
    _radius = radius;
    await _emit();
  }

  @override
  Future<void> vote(String postId, LedgerVoteDirection direction) async {
    // 1. Optimistic local update — the feed reflects the vote immediately.
    //    The repository returns the RESOLVED direction (none when the same
    //    direction toggled off) — that resolved state is what syncs.
    final resolved = await _repository.vote(postId, direction);
    // 2. Best-effort offline-first persistence: record + sealed-enqueue
    //    through the sink. A sink failure must NEVER crash the feed or roll
    //    back the visible vote (graceful sync failure, Task 7.5) — the local
    //    cache stays authoritative and the transport reconciles later.
    try {
      await _votes?.save(LedgerVote(postId: postId, direction: resolved));
    } catch (_) {
      // Persistence is best-effort here; the vote is already applied locally.
    }
    await _emit();
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }

  Future<void> _emit() async {
    final seq = ++_seq;
    final scoped = await _repository.listScoped(
      FeedScope(
        pinCode: _pinCode,
        radius: _radius,
        category: _categoryFilter,
      ),
    );
    final edition = await _repository.currentEdition();
    if (seq != _seq) {
      return; // A newer snapshot landed — drop this stale one.
    }
    final all =
        await _repository.listPosts(pinCode: _pinCode); // unfiltered counts
    final pending = all
        .where((p) =>
            p.status == LedgerPostStatus.peerReview ||
            p.status == LedgerPostStatus.shadowQueue)
        .length;
    if (seq != _seq) {
      return;
    }
    final nearbyPin = scoped.nearbyIds;
    _controller.add(
      LedgerFeedState(
        status: LedgerFeedStatus.loaded,
        pinCode: _pinCode,
        categoryFilter: _categoryFilter,
        edition: edition,
        posts: scoped.posts
            .map((p) => LedgerPostSummary.from(
                  p,
                  nearby: nearbyPin.contains(p.id),
                ))
            .toList(growable: false),
        pendingReviewCount: pending,
        radius: _radius,
        isExpanded: scoped.expanded,
        nearbyCount: scoped.nearbyCount,
      ),
    );
  }
}
