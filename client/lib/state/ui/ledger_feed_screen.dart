import 'dart:async';

import 'package:flutter/material.dart';

import '../../geo/domain/explore_radius.dart';
import '../../ledger/domain/ledger_category.dart';
import '../../ledger/domain/ledger_vote.dart';
import '../domain/ledger_feed_bloc.dart';
import '../domain/ledger_feed_state.dart';
import '../domain/ledger_geo_bloc.dart';
import '../domain/ledger_geo_state.dart';
import '../domain/ledger_review_bloc.dart';
import 'category_chip.dart';
import 'explore_nearby_sheet.dart';
import 'ledger_masthead.dart';
import 'ledger_theme.dart';
import 'ledger_vote_bar.dart';
import 'nearby_badge_widget.dart';
import 'peer_review_queue_section.dart';

/// The Daily Ledger feed screen (DESIGN.md §7.2).
///
/// Consumes the [LedgerFeedBloc] state stream ONLY (clean architecture —
/// no repository/network access from the widget tree). Renders:
/// - the [LedgerMasthead] (nameplate + edition + pin-code scope),
/// - the category filter chips (`All` + one per category),
/// - the post cards (CategoryChip + headline + pin/constituency + vote
///   counts + verified badge),
/// - the Peer Review / Shadow Queue teaser strip,
/// - a "Load older posts" pagination button (NOT infinite scroll),
/// - a compose FAB (Ledger Green).
///
/// SECURITY CHECKPOINT (Task 7.1): authors render ONLY via the non-PII
/// [LedgerPostSummary.authorHandle]; pin codes are public civic scoping;
/// no phones/names/hashes appear in the tree.
class LedgerFeedScreen extends StatefulWidget {
  const LedgerFeedScreen({
    super.key,
    required this.bloc,
    required this.pinCode,
    this.geoBloc,
    this.reviewBloc,
    this.onPostTap,
    this.onCompose,
    this.onLoadOlder,
    this.onRadiusChanged,
  });

  final LedgerFeedBloc bloc;

  /// The user's registered/selected pin code (FR-L2 default scope).
  final String pinCode;

  /// Optional geo-scope bloc (Task 7.2): when present, enables the
  /// Explore Nearby control and shows the coarse scope line in the
  /// masthead.
  final LedgerGeoBloc? geoBloc;

  /// Optional Peer Review Gate bloc (Task 7.6): when present, the passive
  /// teaser strip becomes the interactive review queue (approve/reject/flag
  /// with consensus indicators).
  final LedgerReviewBloc? reviewBloc;

  /// Opens a post detail screen for [postId].
  final ValueChanged<String>? onPostTap;

  /// Opens the compose screen.
  final VoidCallback? onCompose;

  /// Loads older posts (pagination, DESIGN.md §7.2 — no infinite scroll).
  final VoidCallback? onLoadOlder;

  /// Fired when the user picks an Explore Nearby radius.
  final ValueChanged<ExploreRadius>? onRadiusChanged;

  @override
  State<LedgerFeedScreen> createState() => _LedgerFeedScreenState();
}

class _LedgerFeedScreenState extends State<LedgerFeedScreen> {
  StreamSubscription<LedgerGeoState>? _geoSub;

  @override
  void initState() {
    super.initState();
    unawaited(widget.bloc.start(widget.pinCode));
    // The geo bloc resolves the coarse scope AFTER the StreamBuilder below
    // has subscribed (broadcast streams don't replay) — starting here also
    // makes the screen self-contained for the composition root.
    final geo = widget.geoBloc;
    if (geo != null) {
      unawaited(geo.start());
      // Task 7.3: relay the geo radius to the feed bloc so the dynamic
      // radius expansion refetches the scoped feed. (The sheet itself
      // already calls setRadius on the geo bloc; this listener is the
      // geo → feed bridge.)
      _geoSub = geo.state.listen((geoState) {
        unawaited(widget.bloc.setRadius(geoState.radius));
      });
    }
  }

  @override
  void dispose() {
    unawaited(_geoSub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LedgerTheme.paper,
      body: Column(
        children: [
          StreamBuilder<LedgerFeedState>(
            stream: widget.bloc.state,
            builder: (context, snapshot) {
              final state = snapshot.data;
              final geo = widget.geoBloc;
              final masthead = LedgerMasthead(
                // Edition appears once the local cache reports it.
                edition: state?.edition,
                pinCode: widget.pinCode,
              );
              if (geo == null) {
                return masthead;
              }
              // Explore Nearby control (Task 7.2) — a compact radar chip
              // that opens the radius sheet.
              return StreamBuilder<LedgerGeoState>(
                stream: geo.state,
                builder: (context, geoSnapshot) {
                  final geoState = geoSnapshot.data ?? const LedgerGeoState();
                  return _MastheadWithExplore(
                    masthead: masthead,
                    scopeLine: geoState.place?.scopeLine,
                    onExplore: () => _openExploreSheet(geo, geoState),
                  );
                },
              );
            },
          ),
          Expanded(
            child: StreamBuilder<LedgerFeedState>(
              stream: widget.bloc.state,
              builder: (context, snapshot) {
                final state = snapshot.data;
                if (state == null || !state.hasLoaded) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: LedgerTheme.ledgerGreen,
                    ),
                  );
                }
                return _buildFeed(context, state);
              },
            ),
          ),
        ],
      ),
      floatingActionButton: widget.onCompose == null
          ? null
          : FloatingActionButton(
              onPressed: widget.onCompose,
              backgroundColor: LedgerTheme.ledgerGreen,
              tooltip: 'Compose post',
              child: const Icon(Icons.edit_rounded, color: Colors.white),
            ),
    );
  }

  Future<void> _openExploreSheet(
      LedgerGeoBloc geo, LedgerGeoState geoState) async {
    final radius = await showModalBottomSheet<ExploreRadius>(
      context: context,
      backgroundColor: LedgerTheme.paper,
      builder: (_) => ExploreNearbySheet(bloc: geo, state: geoState),
    );
    if (radius != null && widget.onRadiusChanged != null) {
      widget.onRadiusChanged!(radius);
    }
  }

  Widget _buildFeed(BuildContext context, LedgerFeedState state) {
    return ListView(
      children: [
        _CategoryFilterRow(
          selected: state.categoryFilter,
          onSelect: (c) => unawaited(widget.bloc.selectCategory(c)),
        ),
        const Divider(height: 1, color: LedgerTheme.divider),
        if (state.isExpanded && state.nearbyCount > 0) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
            child: Text(
              '~ ${state.nearbyCount} '
              '${state.nearbyCount == 1 ? 'post' : 'posts'} from nearby '
              'pins in this feed ~',
              style: const TextStyle(
                color: LedgerTheme.civicGold,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
        for (final post in state.posts)
          _PostCard(
            post: post,
            onTap: widget.onPostTap,
            onVote: (d) => unawaited(widget.bloc.vote(post.id, d)),
          ),
        if (widget.reviewBloc != null) ...[
          PeerReviewQueueSection(
            bloc: widget.reviewBloc!,
            pinCode: widget.pinCode,
          ),
        ] else if (state.pendingReviewCount > 0) ...[
          const Divider(height: 1, color: LedgerTheme.divider),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(Icons.hourglass_top_rounded,
                    size: 16, color: LedgerTheme.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '~ ${state.pendingReviewCount} '
                    '${state.pendingReviewCount == 1 ? 'post' : 'posts'} in '
                    'Peer Review — tap to preview ~',
                    style: const TextStyle(
                      color: LedgerTheme.muted,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.all(14),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: widget.onLoadOlder,
              style: OutlinedButton.styleFrom(
                foregroundColor: LedgerTheme.ledgerGreen,
                side: const BorderSide(color: LedgerTheme.ledgerGreen),
              ),
              child: const Text('Load older posts'),
            ),
          ),
        ),
      ],
    );
  }
}

/// The `[All] [#Civic] [#Students] ...` filter row (DESIGN.md §7.2).
class _CategoryFilterRow extends StatelessWidget {
  const _CategoryFilterRow({required this.selected, required this.onSelect});

  final LedgerCategory? selected;
  final ValueChanged<LedgerCategory?> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          _AllChip(selected: selected == null, onTap: () => onSelect(null)),
          for (final category in LedgerCategory.values) ...[
            const SizedBox(width: 8),
            CategoryChip(
              category: category,
              selected: selected == category,
              onTap: () => onSelect(category),
            ),
          ],
        ],
      ),
    );
  }
}

class _AllChip extends StatelessWidget {
  const _AllChip({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final background =
        selected ? LedgerTheme.ink : LedgerTheme.ink.withValues(alpha: 0.10);
    final foreground = selected ? Colors.white : LedgerTheme.ink;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: LedgerTheme.ink, width: 1),
        ),
        child: Text(
          'ALL',
          style: TextStyle(
            color: foreground,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}

/// One feed card (DESIGN.md §7.2): chip + time, headline, pin/constituency,
/// interactive vote bar, comment count, verified badge.

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post, this.onTap, this.onVote});

  final LedgerPostSummary post;
  final ValueChanged<String>? onTap;

  /// Casts a vote through the feed bloc (Task 7.5) — interactive vote bar.
  final ValueChanged<LedgerVoteDirection>? onVote;

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
      child: InkWell(
        onTap: onTap == null ? null : () => onTap!(post.id),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CategoryChip(category: post.category),
                  if (post.nearby) ...[
                    const SizedBox(width: 6),
                    const NearbyBadgeWidget(),
                  ],
                  const Spacer(),
                  Text(
                    _timeAgo(post.createdAt),
                    style:
                        const TextStyle(color: LedgerTheme.muted, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                post.headline,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${post.pinCode} · ${post.authorHandle}',
                style: const TextStyle(color: LedgerTheme.muted, fontSize: 12),
              ),
              const Divider(height: 16, color: LedgerTheme.divider),
              Row(
                children: [
                  if (onVote != null)
                    LedgerVoteBar(
                      myVote: post.myVote,
                      karmaScore: post.karmaScore,
                      compact: true,
                      onVote: onVote!,
                    )
                  else
                    _Stat(
                        icon: Icons.arrow_upward_rounded,
                        value: post.karmaScore),
                  const SizedBox(width: 14),
                  _Stat(
                      icon: Icons.chat_bubble_outline_rounded,
                      value: post.commentCount),
                  const Spacer(),
                  if (post.verifiedReviewers > 0)
                    Text(
                      '[✓ Verified — ${post.verifiedReviewers}/3]',
                      style: const TextStyle(
                        color: LedgerTheme.verifiedEmerald,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes} min ago';
    if (diff.inDays < 1) return '${diff.inHours} hrs ago';
    return '${diff.inDays} days ago';
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.value});

  final IconData icon;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: LedgerTheme.muted),
        const SizedBox(width: 4),
        Text('$value', style: const TextStyle(color: LedgerTheme.muted)),
      ],
    );
  }
}

/// The masthead row with the Explore Nearby radar chip (Task 7.2).
class _MastheadWithExplore extends StatelessWidget {
  const _MastheadWithExplore({
    required this.masthead,
    required this.onExplore,
    this.scopeLine,
  });

  final Widget masthead;
  final String? scopeLine;
  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        masthead,
        Container(
          color: LedgerTheme.paper,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  scopeLine ?? 'Resolving your civic scope…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: LedgerTheme.muted,
                    fontSize: 12,
                  ),
                ),
              ),
              InkWell(
                onTap: onExplore,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    border:
                        Border.all(color: LedgerTheme.ledgerGreen, width: 1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.radar_rounded,
                          size: 14, color: LedgerTheme.ledgerGreen),
                      SizedBox(width: 4),
                      Text(
                        'Explore Nearby',
                        style: TextStyle(
                          color: LedgerTheme.ledgerGreen,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
