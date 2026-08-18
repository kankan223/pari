import 'package:civic_commons/karma/domain/karma_calculation.dart';
import 'package:civic_commons/karma/domain/karma_decay.dart';
import 'package:civic_commons/karma/domain/lockstep_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KarmaVoteWeight — sub-linear weighting', () {
    test('documented weight ladder (deterministic)', () {
      expect(KarmaVoteWeight.weight(karma: 0), 1);
      expect(KarmaVoteWeight.weight(karma: 1), 2);
      expect(KarmaVoteWeight.weight(karma: 9), 4); // sqrt(9)=3 → 4
      expect(KarmaVoteWeight.weight(karma: 80), 9); // sqrt(80)=8 → 9
      expect(KarmaVoteWeight.weight(karma: 81), 10); // capped at maxWeight
      expect(KarmaVoteWeight.weight(karma: 10000), 10); // capped
    });

    test('sub-linear: each additional karma adds diminishing weight', () {
      // Increment never grows with karma (non-increasing deltas).
      int prev = 0;
      for (var karma = 0; karma <= 200; karma++) {
        final w = KarmaVoteWeight.weight(karma: karma);
        expect(w, greaterThanOrEqualTo(prev));
        prev = w;
      }
    });

    test('negative karma is treated as zero (never crashes, never negative)',
        () {
      expect(KarmaVoteWeight.weight(karma: -50), 1);
    });
  });

  group('KarmaDecay — −2%/month for inactive accounts', () {
    test('documented decay ladder (deterministic integer math)', () {
      expect(KarmaDecay.decayed(score: 100, monthsInactive: 0), 100);
      expect(KarmaDecay.decayed(score: 100, monthsInactive: 1), 98);
      expect(KarmaDecay.decayed(score: 100, monthsInactive: 2), 96);
      expect(KarmaDecay.decayed(score: 0, monthsInactive: 12), 0);
      expect(KarmaDecay.decayed(score: 1, monthsInactive: 1), 0); // truncates
    });

    test('decay is monotone non-increasing with months', () {
      for (var months = 0; months < 24; months++) {
        final a = KarmaDecay.decayed(score: 1000, monthsInactive: months);
        final b = KarmaDecay.decayed(score: 1000, monthsInactive: months + 1);
        expect(b, lessThanOrEqualTo(a));
      }
    });

    test('inactive 12 months leaves ~78% (documented tolerance)', () {
      final decayed = KarmaDecay.decayed(score: 1000, monthsInactive: 12);
      expect(decayed, greaterThanOrEqualTo(780));
      expect(decayed, lessThanOrEqualTo(800));
    });
  });

  group('LockstepDetector — anomaly detection', () {
    String hash(int n) =>
        n.toRadixString(16).padLeft(64, '0'); // deterministic fake 64-hex

    KarmaVote vote(int n, {int ageDays = 3, int minute = 0}) => KarmaVote(
          voterHash: hash(n),
          accountAgeDays: ageDays,
          at: DateTime.utc(2026, 8, 18, 12, minute),
        );

    test('no cluster → full weight', () {
      expect(
        LockstepDetector.dampeningFor([
          vote(1, ageDays: 400, minute: 0),
          vote(2, ageDays: 900, minute: 2),
        ]),
        LockstepDetector.noDampening,
      );
      expect(LockstepDetector.dampeningFor([]), LockstepDetector.noDampening);
    });

    test('3+ NEW accounts voting within the window dampens to 25%', () {
      final votes = [
        vote(1, ageDays: 2, minute: 0),
        vote(2, ageDays: 5, minute: 1),
        vote(3, ageDays: 10, minute: 3),
      ];
      expect(
        LockstepDetector.dampeningFor(votes),
        LockstepDetector.dampeningFactor,
      );
    });

    test('established accounts in the same window are NOT dampened', () {
      final votes = [
        vote(1, ageDays: 400, minute: 0),
        vote(2, ageDays: 900, minute: 1),
        vote(3, ageDays: 1200, minute: 3),
      ];
      expect(
          LockstepDetector.dampeningFor(votes), LockstepDetector.noDampening);
    });

    test('new accounts OUTSIDE the window are NOT a cluster', () {
      final votes = [
        vote(1, ageDays: 2, minute: 0),
        vote(2, ageDays: 5, minute: 30), // > 10 min after first
        vote(3, ageDays: 10, minute: 45),
      ];
      expect(
          LockstepDetector.dampeningFor(votes), LockstepDetector.noDampening);
    });

    test('two new accounts never dampen (clusterSize = 3)', () {
      expect(
        LockstepDetector.dampeningFor([
          vote(1, ageDays: 2, minute: 0),
          vote(2, ageDays: 5, minute: 1),
        ]),
        LockstepDetector.noDampening,
      );
    });

    test('dampening is deterministic regardless of input order', () {
      final a = [
        vote(3, ageDays: 10, minute: 3),
        vote(1, ageDays: 2, minute: 0),
        vote(2, ageDays: 5, minute: 1),
      ];
      final b = [
        vote(1, ageDays: 2, minute: 0),
        vote(2, ageDays: 5, minute: 1),
        vote(3, ageDays: 10, minute: 3),
      ];
      expect(
          LockstepDetector.dampeningFor(a), LockstepDetector.dampeningFor(b));
    });

    test('dampenedWeight applies the factor to the sub-linear weight', () {
      final cluster = [
        vote(1, ageDays: 2, minute: 0),
        vote(2, ageDays: 5, minute: 1),
        vote(3, ageDays: 10, minute: 3),
      ];
      final base = KarmaVoteWeight.weight(karma: 100).toDouble();
      expect(
        LockstepDetector.dampenedWeight(karma: 100, votes: cluster),
        base * LockstepDetector.dampeningFactor,
      );
    });
  });
}
