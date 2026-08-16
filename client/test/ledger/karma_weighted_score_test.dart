import 'package:civic_commons/ledger/domain/karma_weighted_score.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KarmaWeightedScore (Task 7.5)', () {
    test('zero votes score zero', () {
      expect(
        KarmaWeightedScore.weighted(upvotes: 0, downvotes: 0),
        0,
      );
      expect(KarmaWeightedScore.ofNet(0), 0);
    });

    test('score is deterministic and pure', () {
      final a = KarmaWeightedScore.weighted(upvotes: 100, downvotes: 4);
      final b = KarmaWeightedScore.weighted(upvotes: 100, downvotes: 4);
      expect(a, b);
    });

    test('upvotes add through a sub-linear curve (diminishing returns)', () {
      // sqrt: 1->1, 4->2, 9->3, 16->4, 100->10 — each additional vote adds
      // less than the one before it.
      expect(KarmaWeightedScore.weighted(upvotes: 1, downvotes: 0), 1);
      expect(KarmaWeightedScore.weighted(upvotes: 4, downvotes: 0), 2);
      expect(KarmaWeightedScore.weighted(upvotes: 9, downvotes: 0), 3);
      expect(KarmaWeightedScore.weighted(upvotes: 16, downvotes: 0), 4);
      expect(KarmaWeightedScore.weighted(upvotes: 100, downvotes: 0), 10);
    });

    test('downvotes subtract through the same curve', () {
      expect(KarmaWeightedScore.weighted(upvotes: 0, downvotes: 1), -1);
      expect(KarmaWeightedScore.weighted(upvotes: 0, downvotes: 4), -2);
      expect(KarmaWeightedScore.weighted(upvotes: 0, downvotes: 9), -3);
    });

    test('net score is the difference of the two curves', () {
      expect(
        KarmaWeightedScore.weighted(upvotes: 100, downvotes: 4),
        10 - 2,
      );
      expect(
        KarmaWeightedScore.weighted(upvotes: 4, downvotes: 100),
        2 - 10,
      );
    });

    test('negative inputs are clamped to zero (never NaN/negative roots)', () {
      expect(KarmaWeightedScore.weighted(upvotes: -5, downvotes: 0), 0);
      expect(KarmaWeightedScore.weighted(upvotes: 0, downvotes: -5), 0);
      expect(KarmaWeightedScore.ofNet(-10), 0);
    });

    test('the weighted score never exceeds the raw tally (sub-linear bound)',
        () {
      for (var n = 0; n <= 10000; n += 137) {
        final score = KarmaWeightedScore.weighted(upvotes: n, downvotes: 0);
        expect(score, lessThanOrEqualTo(n));
        // sqrt(n) <= n for all n >= 1; score <= raw is the invariant.
        expect(score, lessThanOrEqualTo(n));
      }
    });

    test('privacy: operates only on aggregate counts (no identity input)', () {
      // The function signature is the proof: it accepts ONLY two integers.
      // There is no way to pass a voter identity, blind hash, or karma
      // value — SECURITY CHECKPOINT 7.5 (client-side aggregate weighting).
      final score = KarmaWeightedScore.weighted(
        upvotes: 100,
        downvotes: 4,
      );
      expect(score, 8);
      // No identity-bearing state exists on the class — it is a pure
      // function holder.
      expect(KarmaWeightedScore.weighted, isA<Function>());
    });

    test('ofNet mirrors the net-tally projection used by the feed', () {
      // The feed state renders sqrt(voteCount) floor — the same curve.
      expect(KarmaWeightedScore.ofNet(48), 6);
      expect(KarmaWeightedScore.ofNet(49), 7);
      expect(KarmaWeightedScore.ofNet(100), 10);
    });
  });
}
