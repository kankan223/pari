import 'package:civic_commons/ledger/domain/ledger_post.dart';
import 'package:civic_commons/ledger/domain/peer_review.dart';
import 'package:civic_commons/ledger/domain/peer_review_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PeerReviewGate - consensus (Task 7.6)', () {
    test('consensus requires exactly 3 approvals', () {
      expect(PeerReviewGate.consensusRequired, 3);
      expect(PeerReviewGate.hasConsensus(0), isFalse);
      expect(PeerReviewGate.hasConsensus(2), isFalse);
      expect(PeerReviewGate.hasConsensus(3), isTrue);
      expect(PeerReviewGate.hasConsensus(4), isTrue);
    });

    test('approving to 3/3 publishes a peer-review post', () {
      expect(
        PeerReviewGate.statusAfterReview(
          current: LedgerPostStatus.peerReview,
          decision: PeerReviewDecision.approved,
          approvedCount: 2,
        ),
        LedgerPostStatus.published,
      );
    });

    test('a single approval leaves the post in review', () {
      expect(
        PeerReviewGate.statusAfterReview(
          current: LedgerPostStatus.peerReview,
          decision: PeerReviewDecision.approved,
          approvedCount: 1,
        ),
        LedgerPostStatus.peerReview,
      );
    });

    test('reject/flag never advance the consensus', () {
      for (final decision in [
        PeerReviewDecision.rejected,
        PeerReviewDecision.flagged,
      ]) {
        expect(
          PeerReviewGate.statusAfterReview(
            current: LedgerPostStatus.peerReview,
            decision: decision,
            approvedCount: 2,
          ),
          LedgerPostStatus.peerReview,
          reason: '${decision.wireName} must not count toward consensus',
        );
      }
    });

    test('published posts are immutable', () {
      expect(
        PeerReviewGate.statusAfterReview(
          current: LedgerPostStatus.published,
          decision: PeerReviewDecision.approved,
          approvedCount: 3,
        ),
        LedgerPostStatus.published,
      );
    });

    test('a shadow-queue post moves to review once reviewed', () {
      // Shadow posts that get reviewed (after their 96h window) enter
      // peer review; they never publish on a single approval.
      expect(
        PeerReviewGate.statusAfterReview(
          current: LedgerPostStatus.shadowQueue,
          decision: PeerReviewDecision.approved,
          approvedCount: 0,
        ),
        LedgerPostStatus.peerReview,
      );
    });
  });

  group('PeerReviewGate - Shadow Queue (FR-L3, Task 7.6)', () {
    test('accounts under 96h post to the shadow queue', () {
      expect(
        PeerReviewGate.entryStatus(
          accountAge: const Duration(hours: 1),
          karma: 500,
        ),
        LedgerPostStatus.shadowQueue,
      );
      expect(
        PeerReviewGate.entryStatus(
          accountAge: const Duration(hours: 95),
          karma: 0,
        ),
        LedgerPostStatus.shadowQueue,
      );
    });

    test('an account exactly at 96h leaves the shadow queue', () {
      expect(
        PeerReviewGate.entryStatus(
          accountAge: PeerReviewGate.shadowQueueWindow,
          karma: 0,
        ),
        LedgerPostStatus.peerReview,
      );
    });

    test('a mature low-karma account enters peer review', () {
      expect(
        PeerReviewGate.entryStatus(
          accountAge: const Duration(days: 30),
          karma: 10,
        ),
        LedgerPostStatus.peerReview,
      );
    });

    test('a high-karma account fast-tracks to published', () {
      expect(
        PeerReviewGate.entryStatus(
          accountAge: const Duration(days: 30),
          karma: PeerReviewGate.fastTrackKarmaThreshold,
        ),
        LedgerPostStatus.published,
      );
      // Even a young high-karma account is held by the shadow window
      // (shadow queue is the stronger gate — FR-L3 precedes fast-track).
      expect(
        PeerReviewGate.entryStatus(
          accountAge: const Duration(hours: 12),
          karma: 1000,
        ),
        LedgerPostStatus.shadowQueue,
      );
    });

    test('entry status is deterministic (pure function)', () {
      LedgerPostStatus run() => PeerReviewGate.entryStatus(
            accountAge: const Duration(days: 3),
            karma: 50,
          );
      expect(run(), run());
    });
  });

  group('PeerReviewGate - blinded reviewer assignment (Task 7.6)', () {
    final hashes = List.generate(
      8,
      (i) => '${i + 1}'.padLeft(64, 'a'),
      growable: false,
    );

    test('assigns exactly 3 reviewers when the pool is large enough', () {
      final reviewers = PeerReviewGate.assignReviewers('post_1', hashes);
      expect(reviewers, hasLength(3));
    });

    test('assignment is deterministic (same post, same pool -> same set)', () {
      final a = PeerReviewGate.assignReviewers('post_1', hashes);
      final b = PeerReviewGate.assignReviewers('post_1', hashes);
      expect(a, b);
    });

    test('different posts assign different reviewer sets', () {
      final a = PeerReviewGate.assignReviewers('post_1', hashes);
      final b = PeerReviewGate.assignReviewers('post_2', hashes);
      expect(a, isNot(equals(b)));
    });

    test('handles are DERIVED display handles — never raw blind hashes', () {
      final reviewers = PeerReviewGate.assignReviewers('post_1', hashes);
      for (final handle in reviewers) {
        expect(handle.startsWith('reviewer_'), isTrue);
        // The 6-char digest is a display fragment, NOT the 64-hex hash.
        expect(handle.length, 15); // 'reviewer_' + 6 hex + 1
        expect(RegExp(r'[0-9a-f]{64}').hasMatch(handle), isFalse);
        expect(hashes.contains(handle), isFalse);
      }
    });

    test('empty pool yields no reviewers (safe default)', () {
      expect(PeerReviewGate.assignReviewers('post_1', const []), isEmpty);
    });

    test('blindedHandleFor is deterministic and never equals the input', () {
      const raw =
          'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2';
      final handle = PeerReviewGate.blindedHandleFor(raw);
      expect(handle, PeerReviewGate.blindedHandleFor(raw));
      expect(handle, isNot(raw));
      expect(RegExp(r'[0-9a-f]{64}').hasMatch(handle), isFalse);
    });
  });
}
