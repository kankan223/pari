import 'package:flutter/material.dart';

import '../../ledger/domain/ledger_vote.dart';
import 'ledger_theme.dart';

/// The Ledger vote bar (Task 7.5) — upvote / karma-weighted score /
/// downvote, used on feed cards and the post detail screen.
///
/// SECURITY CHECKPOINT (Task 7.5): renders ONLY the karma-weighted score
/// and the local device's active direction — no identity, no PII, no blind
/// hashes. The score is the deterministic client-side projection computed by
/// the state layer; this widget never computes or displays raw tallies.
class LedgerVoteBar extends StatelessWidget {
  const LedgerVoteBar({
    super.key,
    required this.myVote,
    required this.karmaScore,
    required this.onVote,
    this.compact = false,
    this.iconSize = 20,
  });

  /// The local device's current vote (drives the active states).
  final LedgerVoteDirection myVote;

  /// The karma-weighted score to display.
  final int karmaScore;

  /// Fired when the user taps a direction (the caller toggles through the
  /// bloc — same-direction taps remove the vote).
  final ValueChanged<LedgerVoteDirection> onVote;

  /// Compact layout for feed cards (smaller hit targets + spacing).
  final bool compact;

  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final upActive = myVote == LedgerVoteDirection.up;
    final downActive = myVote == LedgerVoteDirection.down;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _VoteArrow(
          icon: Icons.arrow_upward_rounded,
          active: upActive,
          color: LedgerTheme.verifiedEmerald,
          size: iconSize,
          onTap: () => onVote(LedgerVoteDirection.up),
        ),
        SizedBox(width: compact ? 2 : 6),
        Text(
          '$karmaScore',
          style: TextStyle(
            color: LedgerTheme.ink,
            fontWeight: FontWeight.w600,
            fontSize: compact ? 13 : 15,
          ),
        ),
        SizedBox(width: compact ? 2 : 6),
        _VoteArrow(
          icon: Icons.arrow_downward_rounded,
          active: downActive,
          color: LedgerTheme.alertRed,
          size: iconSize,
          onTap: () => onVote(LedgerVoteDirection.down),
        ),
      ],
    );
  }
}

class _VoteArrow extends StatelessWidget {
  const _VoteArrow({
    required this.icon,
    required this.active,
    required this.color,
    required this.size,
    required this.onTap,
  });

  final IconData icon;
  final bool active;
  final Color color;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fill = active ? color : LedgerTheme.muted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Icon(
          icon,
          size: size,
          color: fill,
          // Active direction reads as a filled arrow; inactive stays outline.
          weight: active ? 700 : 400,
        ),
      ),
    );
  }
}
