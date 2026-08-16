import 'dart:async';

import 'package:flutter/material.dart';

import '../../ledger/domain/peer_review.dart';
import '../domain/ledger_review_bloc.dart';
import '../domain/ledger_review_state.dart';
import 'ledger_theme.dart';

/// The Peer Review Gate queue section (Task 7.6, DESIGN.md §7.2).
///
/// Renders the posts awaiting review with approve / reject / flag controls
/// and the `[✓ Peer Review Gate: N/3 approved]` consensus indicator. All
/// actions flow through the [LedgerReviewBloc] — the widget never touches a
/// repository or the network.
///
/// SECURITY CHECKPOINT (Task 7.6): renders ONLY non-PII author handles,
/// public civic content, blinded reviewer handles, and fixed labels — never
/// raw blind hashes, phones, or names.
class PeerReviewQueueSection extends StatefulWidget {
  const PeerReviewQueueSection({
    super.key,
    required this.bloc,
    required this.pinCode,
  });

  final LedgerReviewBloc bloc;
  final String pinCode;

  @override
  State<PeerReviewQueueSection> createState() => _PeerReviewQueueSectionState();
}

class _PeerReviewQueueSectionState extends State<PeerReviewQueueSection> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.bloc.start(widget.pinCode));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<LedgerReviewState>(
      stream: widget.bloc.state,
      builder: (context, snapshot) {
        final state = snapshot.data;
        if (state == null || !state.hasLoaded) {
          return const SizedBox.shrink();
        }
        return _buildQueue(context, state);
      },
    );
  }

  Widget _buildQueue(BuildContext context, LedgerReviewState state) {
    if (state.queue.isEmpty && state.shadowQueueCount == 0) {
      return const SizedBox.shrink();
    }
    final children = <Widget>[
      const Divider(height: 1, color: LedgerTheme.divider),
      const Padding(
        padding: EdgeInsets.fromLTRB(14, 12, 14, 4),
        child: Text(
          'PEER REVIEW GATE',
          style: TextStyle(
            color: LedgerTheme.ink,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      ),
      if (state.shadowQueueCount > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 2),
          child: Text(
            '~ ${state.shadowQueueCount} '
            '${state.shadowQueueCount == 1 ? 'post' : 'posts'} in the '
            'Shadow Queue (new-account hold, <96h) ~',
            style: const TextStyle(
              color: LedgerTheme.civicGold,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      for (final entry in state.queue)
        _ReviewCard(
          entry: entry,
          onApprove: () => unawaited(
              widget.bloc.submit(entry.postId, PeerReviewDecision.approved)),
          onReject: () => unawaited(
              widget.bloc.submit(entry.postId, PeerReviewDecision.rejected)),
          onFlag: () => unawaited(
              widget.bloc.submit(entry.postId, PeerReviewDecision.flagged)),
        ),
    ];
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

/// Defensively blinds a hash-shaped handle: a raw 64-hex blind hash is
/// truncated to a `reviewer_`-style fragment before it can reach the widget
/// tree (SECURITY CHECKPOINT 7.6 — a full hash rendered anywhere could be
/// shoulder-surfed as an identifier). Non-hash display handles pass through
/// unchanged.
String _safeHandle(String handle) {
  final trimmed = handle.trim();
  if (RegExp(r'^[0-9a-f]{64}$').hasMatch(trimmed)) {
    return 'reviewer_${trimmed.substring(0, 6)}';
  }
  return trimmed;
}

/// One review card: headline, blinded reviewers, consensus indicator, and
/// approve / reject / flag controls.
class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.entry,
    required this.onApprove,
    required this.onReject,
    required this.onFlag,
  });

  final ReviewQueueEntry entry;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onFlag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: LedgerTheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: const BorderSide(color: LedgerTheme.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  entry.categoryLabel,
                  style: const TextStyle(
                    color: LedgerTheme.civicGold,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
                const Spacer(),
                Text(
                  entry.reviewedByMe ? 'REVIEWED' : 'AWAITING REVIEW',
                  style: TextStyle(
                    color: entry.reviewedByMe
                        ? LedgerTheme.verifiedEmerald
                        : LedgerTheme.alertRed,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              entry.headline,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              // Non-PII author handle + blinded reviewers only. The author
              // handle is defensively re-blinded here (never render a raw
              // 64-hex string even if one slipped into the projection).
              'by ${_safeHandle(entry.authorHandle)} · '
              '${entry.reviewerHandles.join(' · ')}',
              style: const TextStyle(color: LedgerTheme.muted, fontSize: 11),
            ),
            const SizedBox(height: 8),
            Text(
              entry.consensusReached
                  ? '[✓ Peer Review Gate: 3/3 — PUBLISHED]'
                  : '[✓ Peer Review Gate: ${entry.verifiedReviewers}/3 approved]',
              style: TextStyle(
                color: entry.consensusReached
                    ? LedgerTheme.verifiedEmerald
                    : LedgerTheme.civicGold,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            // Controls are hidden once the local device has reviewed the
            // post OR the 3/3 gate has already passed (published).
            if (!entry.reviewedByMe && !entry.consensusReached) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  _ActionButton(
                    label: 'APPROVE',
                    foreground: LedgerTheme.verifiedEmerald,
                    onTap: onApprove,
                  ),
                  const SizedBox(width: 8),
                  _ActionButton(
                    label: 'REJECT',
                    foreground: LedgerTheme.alertRed,
                    onTap: onReject,
                  ),
                  const SizedBox(width: 8),
                  _ActionButton(
                    label: 'FLAG',
                    foreground: LedgerTheme.civicGold,
                    onTap: onFlag,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: foreground,
        side: BorderSide(color: foreground),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: const Size(0, 30),
        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
      child: Text(label),
    );
  }
}
