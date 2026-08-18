import 'package:civic_commons/karma/domain/karma_badge.dart';
import 'package:civic_commons/state/domain/karma_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KarmaBadge.forBalance', () {
    test('balance 0 maps to citizen', () {
      final badge = KarmaBadge.forBalance(0);
      expect(badge.tier, KarmaTier.citizen);
      expect(badge.label, 'Citizen');
    });

    test('balance 49 stays citizen', () {
      final badge = KarmaBadge.forBalance(49);
      expect(badge.tier, KarmaTier.citizen);
    });

    test('balance 50 maps to contributor', () {
      final badge = KarmaBadge.forBalance(50);
      expect(badge.tier, KarmaTier.contributor);
      expect(badge.label, 'Contributor');
    });

    test('balance 99 stays contributor', () {
      final badge = KarmaBadge.forBalance(99);
      expect(badge.tier, KarmaTier.contributor);
    });

    test('balance 100 maps to validator', () {
      final badge = KarmaBadge.forBalance(100);
      expect(badge.tier, KarmaTier.validator);
      expect(badge.label, 'Validator');
    });

    test('balance 149 stays validator', () {
      final badge = KarmaBadge.forBalance(149);
      expect(badge.tier, KarmaTier.validator);
    });

    test('balance 150 maps to analyst', () {
      final badge = KarmaBadge.forBalance(150);
      expect(badge.tier, KarmaTier.analyst);
      expect(badge.label, 'Analyst');
    });

    test('balance 499 stays analyst', () {
      final badge = KarmaBadge.forBalance(499);
      expect(badge.tier, KarmaTier.analyst);
    });

    test('balance 500 maps to council', () {
      final badge = KarmaBadge.forBalance(500);
      expect(badge.tier, KarmaTier.council);
      expect(badge.label, 'Council');
    });

    test('balance 9999 stays council', () {
      final badge = KarmaBadge.forBalance(9999);
      expect(badge.tier, KarmaTier.council);
    });

    test('badge is deterministic — same balance always yields same badge', () {
      final a = KarmaBadge.forBalance(247);
      final b = KarmaBadge.forBalance(247);
      expect(a.tier, b.tier);
      expect(a.label, b.label);
      expect(a.color, b.color);
      expect(a.icon, b.icon);
    });
  });

  group('KarmaBadge.forTier', () {
    test('forTier returns same badge as forBalance at tier minimum', () {
      for (final tier in KarmaTier.values) {
        final fromTier = KarmaBadge.forTier(tier);
        final fromBalance = KarmaBadge.forBalance(tier.minimum);
        expect(fromTier.tier, fromBalance.tier);
        expect(fromTier.label, fromBalance.label);
      }
    });
  });

  group('KarmaBadge tier progression', () {
    test('higher balance always yields same or higher tier', () {
      KarmaTier prev = KarmaTier.forBalance(0);
      for (final balance in [0, 10, 49, 50, 75, 99, 100, 125, 149, 150, 300, 499, 500, 1000]) {
        final current = KarmaTier.forBalance(balance);
        expect(current.index >= prev.index, true,
            reason: 'Balance $balance tier ${current.label} should be >= ${prev.label}');
        prev = current;
      }
    });
  });

  group('KarmaBadge description', () {
    test('all tiers have non-empty descriptions', () {
      for (final tier in KarmaTier.values) {
        final badge = KarmaBadge.forTier(tier);
        expect(badge.description.isNotEmpty, true);
      }
    });
  });
}
