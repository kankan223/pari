import 'package:civic_commons/karma/domain/karma_action.dart';
import 'package:civic_commons/karma/domain/karma_gate.dart';
import 'package:civic_commons/state/domain/karma_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KarmaTier — DESIGN §4.3 bands', () {
    test('band boundaries are deterministic', () {
      expect(KarmaTier.forBalance(0), KarmaTier.citizen);
      expect(KarmaTier.forBalance(49), KarmaTier.citizen);
      expect(KarmaTier.forBalance(50), KarmaTier.contributor);
      expect(KarmaTier.forBalance(99), KarmaTier.contributor);
      expect(KarmaTier.forBalance(100), KarmaTier.validator);
      expect(KarmaTier.forBalance(149), KarmaTier.validator);
      expect(KarmaTier.forBalance(150), KarmaTier.analyst);
      expect(KarmaTier.forBalance(499), KarmaTier.analyst);
      expect(KarmaTier.forBalance(500), KarmaTier.council);
      expect(KarmaTier.forBalance(50000), KarmaTier.council);
    });

    test('negative balances stay citizen', () {
      expect(KarmaTier.forBalance(-25), KarmaTier.citizen);
    });

    test('tier labels are fixed and non-empty', () {
      for (final tier in KarmaTier.values) {
        expect(tier.label.trim(), isNotEmpty);
      }
    });
  });
  group('KarmaState', () {
    test('ready state carries balance, tier, gates, and activity', () {
      final state = KarmaState.ready(
        balance: 247,
        gates: const {},
        activity: [
          KarmaActivity(
            action: KarmaAction.warRoomAnalystVetted,
            delta: 20,
            at: DateTime.utc(2026, 8, 18),
          ),
        ],
      );
      expect(state.isReady, isTrue);
      expect(state.tier, KarmaTier.analyst);
      expect(state.activity.single.action, KarmaAction.warRoomAnalystVetted);
    });

    test('activity rows are UI-safe projections (no actor hash)', () {
      final row = KarmaActivity(
        action: KarmaAction.ledgerPostVerified,
        delta: 5,
        at: DateTime.utc(2026, 8, 18),
      );
      expect(row.action, KarmaAction.ledgerPostVerified);
      expect(row.delta, 5);
      expect(row.at, DateTime.utc(2026, 8, 18));
      // The projection exposes ONLY action + delta + timestamp — a blind
      // hash / event id / actor can never reach state (SECURITY
      // CHECKPOINT 10.2). The structural proof lives in the security
      // checkpoint suite (source scan of the state file).
    });

    test('default state is idle with zero balance and citizen tier', () {
      const state = KarmaState();
      expect(state.phase, KarmaPhase.idle);
      expect(state.balance, 0);
      expect(state.tier, KarmaTier.citizen);
      expect(state.satisfied(KarmaGate.skipProbationPosting), isFalse);
    });

    test('error state is payload-free', () {
      const state = KarmaState.error('generic');
      expect(state.isError, isTrue);
      expect(state.errorMessage, isNotEmpty);
      expect(state.balance, 0);
      expect(state.activity, isEmpty);
      expect(state.tier, KarmaTier.citizen);
    });

    test('satisfied() reads the gates map', () {
      const gated = KarmaState.ready(
        balance: 100,
        gates: {KarmaGate.peerReviewVoting: true},
        activity: [],
      );
      expect(gated.satisfied(KarmaGate.peerReviewVoting), isTrue);
      expect(gated.satisfied(KarmaGate.skipProbationPosting), isFalse);
    });
  });
}
