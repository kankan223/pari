import 'package:flutter/material.dart';

import '../domain/karma_badge.dart';
import '../../state/domain/karma_state.dart';

/// A compact inline chip showing a karma tier label + icon (Task 10.3).
///
/// Designed for embedding in list tiles, cards, and participant rows across
/// all four pillars. The chip consumes ONLY a public [KarmaTier] or integer
/// balance — never a blind hash, never an identity.
///
/// When [tier] is null the chip renders nothing (the parent screen doesn't
/// have karma data for this entity), keeping wiring non-breaking.
///
/// SECURITY CHECKPOINT (10.3): the chip renders only the fixed [KarmaBadge]
/// tokens (color + icon + label). No identity fields, no raw hashes, no PII
/// can reach the widget tree through this component.
class KarmaTierChip extends StatelessWidget {
  /// The karma tier to display. When null, renders nothing.
  final KarmaTier? tier;

  /// When [tier] is null but [balance] is provided, the tier is derived
  /// deterministically from the balance.
  final int? balance;

  /// Compact mode: smaller icon + text for tight list rows.
  final bool compact;

  const KarmaTierChip({
    super.key,
    this.tier,
    this.balance,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveTier =
        tier ?? (balance != null ? KarmaTier.forBalance(balance!) : null);
    if (effectiveTier == null) return const SizedBox.shrink();

    final badge = KarmaBadge.forTier(effectiveTier);
    final iconSize = compact ? 12.0 : 14.0;
    final fontSize = compact ? 9.0 : 10.0;
    final hPadding = compact ? 5.0 : 7.0;
    final vPadding = compact ? 2.0 : 3.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPadding, vertical: vPadding),
      decoration: BoxDecoration(
        color: badge.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(compact ? 3 : 4),
        border: Border.all(color: badge.color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(badge.icon, size: iconSize, color: badge.color),
          SizedBox(width: compact ? 3 : 4),
          Text(
            badge.label.toUpperCase(),
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: badge.color,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}
