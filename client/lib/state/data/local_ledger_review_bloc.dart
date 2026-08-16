import 'dart:async';

import '../../ledger/domain/ledger_feed_repository.dart';
import '../../ledger/domain/ledger_post.dart';
import '../../ledger/domain/peer_review.dart';
import '../../ledger/domain/peer_review_gate.dart';
import '../../ledger/domain/peer_review_sink.dart';
import '../domain/ledger_review_bloc.dart';
import '../domain/ledger_review_state.dart';

/// Local-cache-backed [LedgerReviewBloc] (data layer, Task 7.6).
///
/// Reads the review queue ONLY from the injected [LedgerFeedRepository] —
/// the offline-first contract. Review decisions are applied locally
/// (consensus resolved client-side) and persisted through the optional
/// [PeerReviewSink] (offline-first record + sealed enqueue). A failing sink
/// degrades gracefully — the local decision stays applied, never a crash.
class LocalLedgerReviewBloc implements LedgerReviewBloc {
  final LedgerFeedRepository _repository;
  final PeerReviewSink? _reviews;

  final StreamController<LedgerReviewState> _controller =
      StreamController<LedgerReviewState>.broadcast();

  String _pinCode = '';

  /// Post ids already reviewed by the local device this session.
  final Set<String> _reviewed = {};

  /// Monotonic snapshot sequence — a stale pull can never overwrite a
  /// fresher one (codebase convention).
  int _seq = 0;

  LocalLedgerReviewBloc({
    required LedgerFeedRepository repository,
    PeerReviewSink? reviews,
  })  : _repository = repository,
        _reviews = reviews;

  @override
  Stream<LedgerReviewState> get state => _controller.stream;

  @override
  Future<void> start(String pinCode) async {
    _pinCode = pinCode;
    await _emit();
  }

  @override
  Future<void> submit(String postId, PeerReviewDecision decision) async {
    // 1. Apply locally — consensus transitions are resolved client-side.
    await _repository.applyReview(postId, decision);
    _reviewed.add(postId);
    // 2. Best-effort offline-first persistence: record + sealed-enqueue
    //    through the sink. A sink failure must NEVER crash the queue or roll
    //    back the visible decision (graceful sync failure, Task 7.6).
    try {
      await _reviews?.save(
        PeerReviewSubmission(postId: postId, decision: decision),
      );
    } catch (_) {
      // Persistence is best-effort here; the decision is already applied.
    }
    await _emit();
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }

  Future<void> _emit() async {
    final seq = ++_seq;
    final all = await _repository.listPosts(pinCode: _pinCode);
    if (seq != _seq) {
      return;
    }
    final inReview = all
        .where((p) =>
            p.status == LedgerPostStatus.peerReview ||
            p.status == LedgerPostStatus.shadowQueue)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final shadow =
        all.where((p) => p.status == LedgerPostStatus.shadowQueue).length;
    _controller.add(
      LedgerReviewState(
        status: LedgerReviewStatus.loaded,
        queue: inReview.map((p) => _entry(p)).toList(growable: false),
        shadowQueueCount: shadow,
      ),
    );
  }

  ReviewQueueEntry _entry(LedgerPost post) {
    final candidates = <String>[
      // Deterministic blinded reviewer assignment from the post's own
      // opaque handles — the handles rendered are derived, never raw.
      '${post.pinCode}${post.id}',
      '${post.id}${post.authorHandle}',
    ];
    final reviewers = PeerReviewGate.assignReviewers(post.id, candidates);
    return ReviewQueueEntry(
      postId: post.id,
      headline: post.headline,
      categoryLabel: post.category.label,
      authorHandle: post.authorHandle,
      verifiedReviewers: post.verifiedReviewers,
      reviewedByMe: _reviewed.contains(post.id),
      reviewerHandles: reviewers,
    );
  }
}
