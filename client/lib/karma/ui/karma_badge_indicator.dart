import 'package:flutter/material.dart';

import '../domain/karma_badge.dart';
import '../../state/domain/karma_state.dart';

/// A larger karma badge display for detail views and profile cards (Task 10.3).
///
/// Shows the tier icon + label + optional balance. Designed for cases where
/// more visual weight is appropriate (analyst team cards, study group
/// participant rows, conversation detail headers).
///
/// When [tier] is null, renders nothing — keeping cross-pillar wiring
/// non-breaking when karma data isn't available.
///
/// SECURITY CHECKPOINT (10.3): renders ONLY the fixed [KarmaBadge] tokens
/// (color, icon, label) and optionally the public integer balance. No
/// identity, no blind hash, no PII.
class KarmaBadgeIndicator extends StatelessWidget {
  final KarmaTier? tier;
  final int? balance;

  const KarmaBadgeIndicator({
    super.key,
    this.tier,
    this.balance,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveTier =
        tier ?? (balance != null ? KarmaTier.forBalance(balance!) : null);
    if (effectiveTier == null) return const SizedBox.shrink();

    final badge = KarmaBadge.forTier(effectiveTier);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(badge.icon, size: 16, color: badge.color),
        const SizedBox(width: 5),
        Text(
          badge.label.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: badge.color,
            letterSpacing: 0.8,
          ),
        ),
        if (balance != null) ...[
          const SizedBox(width: 4),
          Text(
            '$balance',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: badge.color.withValues(alpha: 0.7),
            ),
          ),
        ],
      ],
    );
  }
}
