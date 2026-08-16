import 'dart:async';

import 'package:flutter/material.dart';

import '../../ledger/domain/karma_weighted_score.dart';
import '../../ledger/domain/ledger_post.dart';
import '../../ledger/domain/ledger_vote.dart';
import '../domain/ledger_feed_bloc.dart';
import 'category_chip.dart';
import 'ledger_theme.dart';
import 'ledger_vote_bar.dart';

/// The Daily Ledger post detail screen (DESIGN.md §7.4).
///
/// Renders the full post body, the `Posted by` meta line, the Peer Review
/// Gate badge, evidence attachments (read-only placeholder), vote controls,
/// and the replies section. Voting flows through the [LedgerFeedBloc] so
/// the aggregate count stays in sync with the feed.
///
/// SECURITY CHECKPOINT (Task 7.1): identity renders ONLY as the non-PII
/// author tier line (`Posted by ★ Analyst-tier`) — never a phone, name,
/// or hash. Post content is public civic content by design.
class LedgerPostDetailScreen extends StatefulWidget {
  const LedgerPostDetailScreen({
    super.key,
    required this.bloc,
    required this.post,
    this.onBack,
    this.onShare,
    this.onFlag,
  });

  final LedgerFeedBloc bloc;
  final LedgerPost post;

  final VoidCallback? onBack;
  final VoidCallback? onShare;
  final VoidCallback? onFlag;

  @override
  State<LedgerPostDetailScreen> createState() => _LedgerPostDetailScreenState();
}

class _LedgerPostDetailScreenState extends State<LedgerPostDetailScreen> {
  /// The live post (vote counts update as the bloc applies deltas).
  late LedgerPost _post = widget.post;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final post = _post;
    return Scaffold(
      backgroundColor: LedgerTheme.paper,
      appBar: AppBar(
        backgroundColor: LedgerTheme.paper,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: widget.onBack ?? () => Navigator.of(context).maybePop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.flag_outlined, size: 20),
            tooltip: 'Flag post',
            onPressed: widget.onFlag,
          ),
          IconButton(
            icon: const Icon(Icons.ios_share_rounded, size: 20),
            tooltip: 'Share',
            onPressed: widget.onShare,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              CategoryChip(category: post.category),
              const Spacer(),
              Text(
                post.pinCode,
                style: const TextStyle(
                  color: LedgerTheme.muted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            post.headline,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontFamily: 'serif',
              height: 1.25,
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: LedgerTheme.divider),
          const SizedBox(height: 8),
          Text(
            // DESIGN.md §7.4: tier line, never an identity handle.
            'Posted by ★ ${_tierLabel(post)}',
            style: const TextStyle(color: LedgerTheme.muted, fontSize: 12),
          ),
          if (post.verifiedReviewers > 0) ...[
            const SizedBox(height: 4),
            Text(
              '[✓ Peer Review Gate: ${post.verifiedReviewers}/3 '
              'approved]',
              style: TextStyle(
                color: post.verifiedReviewers == 3
                    ? LedgerTheme.verifiedEmerald
                    : LedgerTheme.civicGold,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const Divider(height: 20, color: LedgerTheme.divider),
          Text(
            post.body,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontSize: 16,
              height: 1.5,
              fontFamily: 'NotoSans',
            ),
          ),
          const SizedBox(height: 16),
          // Evidence attachments (read-only placeholders — the media layer
          // lands with the compose/upload task).
          const Text(
            '[Evidence: no attachments yet]',
            style: TextStyle(
              color: LedgerTheme.muted,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
          const Divider(height: 24, color: LedgerTheme.divider),
          Row(
            children: [
              // Task 7.5: interactive vote bar — active direction state +
              // karma-weighted score, toggling through the bloc.
              LedgerVoteBar(
                myVote: post.myVote,
                karmaScore: _karmaScore(post),
                onVote: (d) => unawaited(_vote(d)),
              ),
              const Spacer(),
              Text(
                '💬 ${post.commentCount} Replies',
                style: const TextStyle(
                  color: LedgerTheme.muted,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const Divider(height: 24, color: LedgerTheme.divider),
          // Replies section — threaded replies land with the comment task.
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No replies yet — be the first to respond.',
                style: TextStyle(
                  color: LedgerTheme.muted,
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _vote(LedgerVoteDirection direction) async {
    // Optimistic local update: apply the toggle to the displayed post the
    // same way the repository will (the bloc re-emits the authoritative
    // snapshot after the repository applies it).
    final current = _post.myVote;
    final next = current == direction ? LedgerVoteDirection.none : direction;
    final delta = next.delta - current.delta;
    // Optimistic: mirror the repository toggle (net tally may go negative —
    // the karma display clamps negatives at the projection layer).
    final updated = _post.copyWith(
      voteCount: _post.voteCount + delta,
      myVote: next,
    );
    setState(() => _post = updated);
    await widget.bloc.vote(_post.id, direction);
  }

  /// The karma-weighted sub-linear projection of the post's net tally
  /// (same deterministic function the feed state uses — Task 7.5).
  int _karmaScore(LedgerPost post) => KarmaWeightedScore.ofNet(post.voteCount);

  String _tierLabel(LedgerPost post) {
    // DESIGN.md §7.3 karma tiers — non-PII, purely derived from the post's
    // review status (no identity data involved).
    if (post.status == LedgerPostStatus.peerReview) return 'Contributor';
    if (post.verifiedReviewers == 3) return 'Analyst';
    return 'Citizen';
  }
}
